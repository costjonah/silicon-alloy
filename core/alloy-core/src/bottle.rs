use crate::runtime::{RuntimeLocator, RuntimeMetadata};
use anyhow::{anyhow, bail, Context, Result};
use dirs::home_dir;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::time::Duration;
use std::{fs, str::FromStr};
use tokio::fs::{create_dir_all, remove_dir_all, OpenOptions};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::process::Command;
use tokio::sync::Mutex;
use tokio::time::timeout;
use uuid::Uuid;

use std::sync::Arc;

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct BottleMetadata {
    pub id: Uuid,
    pub name: String,
    pub created_at: String,
    pub runtime: RuntimeMetadata,
    pub notes: Option<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct BottleSummary {
    pub name: String,
    pub path: PathBuf,
    pub runtime: RuntimeMetadata,
}

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct BottleName(String);

impl BottleName {
    pub fn as_str(&self) -> &str {
        &self.0
    }

    fn sanitize(input: &str) -> Option<String> {
        let trimmed = input.trim();
        if trimmed.is_empty() {
            return None;
        }

        let mut clean = String::new();
        for ch in trimmed.chars() {
            match ch {
                'a'..='z' | 'A'..='Z' | '0'..='9' => clean.push(ch.to_ascii_lowercase()),
                '-' | '_' => clean.push(ch),
                ' ' => clean.push('-'),
                _ => continue,
            }
        }

        let clean = clean.trim_matches(['-', '_'].as_ref());
        if clean.is_empty() {
            None
        } else {
            Some(clean.to_string())
        }
    }
}

impl FromStr for BottleName {
    type Err = anyhow::Error;

    fn from_str(value: &str) -> Result<Self, Self::Err> {
        BottleName::sanitize(value)
            .map(Self)
            .ok_or_else(|| anyhow!("please pick a bottle name that uses letters, numbers, dashes, or underscores"))
    }
}

pub struct BottleManager {
    bottles_dir: PathBuf,
    logs_dir: PathBuf,
    runtime: RuntimeLocator,
}

impl BottleManager {
    pub fn new(runtime: RuntimeLocator) -> Result<Self> {
        let base = data_root()?;
        let bottles_dir = base.join("bottles");
        let logs_dir = base.join("logs");
        fs::create_dir_all(&bottles_dir)
            .with_context(|| format!("unable to create bottle directory at {}", bottles_dir.display()))?;
        fs::create_dir_all(&logs_dir)
            .with_context(|| format!("unable to create logs directory at {}", logs_dir.display()))?;

        Ok(Self {
            bottles_dir,
            logs_dir,
            runtime,
        })
    }

    pub fn runtime(&self) -> &RuntimeLocator {
        &self.runtime
    }

    fn bottle_path(&self, name: &BottleName) -> PathBuf {
        self.bottles_dir.join(name.as_str())
    }

    fn metadata_path(&self, name: &BottleName) -> PathBuf {
        self.bottle_path(name).join("silicon-alloy.json")
    }

    fn log_path(&self, name: &BottleName) -> PathBuf {
        self.logs_dir.join(format!("{}.log", name.as_str()))
    }

    pub fn bottle_prefix(&self, name: &BottleName) -> PathBuf {
        self.bottle_path(name)
    }

    pub async fn create_bottle(&self, name: &BottleName) -> Result<BottleMetadata> {
        let prefix_path = self.bottle_path(name);
        if prefix_path.exists() {
            bail!("bottle {} already exists", name.as_str());
        }

        create_dir_all(&prefix_path).await?;

        self.bootstrap_prefix(&prefix_path).await?;

        let created_at = time::OffsetDateTime::now_utc().format(&time::format_description::well_known::Rfc3339)?;
        let metadata = BottleMetadata {
            id: Uuid::new_v4(),
            name: name.as_str().to_string(),
            created_at,
            runtime: self.runtime.metadata().clone(),
            notes: None,
        };

        let serialized = serde_json::to_vec_pretty(&metadata)?;
        tokio::fs::write(self.metadata_path(name), serialized).await?;
        Ok(metadata)
    }

    pub async fn list_bottles(&self) -> Result<Vec<BottleSummary>> {
        let mut summaries = Vec::new();
        let mut entries = tokio::fs::read_dir(&self.bottles_dir).await?;
        while let Some(entry) = entries.next_entry().await? {
            if !entry.file_type().await?.is_dir() {
                continue;
            }
            let name = entry.file_name().into_string().unwrap_or_default();
            let metadata_path = entry.path().join("silicon-alloy.json");
            if !metadata_path.exists() {
                continue;
            }
            let bytes = tokio::fs::read(&metadata_path).await?;
            if let Ok(metadata) = serde_json::from_slice::<BottleMetadata>(&bytes) {
                summaries.push(BottleSummary {
                    name,
                    path: entry.path(),
                    runtime: metadata.runtime,
                });
            }
        }
        summaries.sort_by(|a, b| a.name.cmp(&b.name));
        Ok(summaries)
    }

    pub async fn destroy_bottle(&self, name: &BottleName) -> Result<()> {
        let prefix_path = self.bottle_path(name);
        if !prefix_path.exists() {
            bail!("bottle {} does not exist", name.as_str());
        }
        remove_dir_all(&prefix_path).await?;
        let log_path = self.log_path(name);
        if log_path.exists() {
            tokio::fs::remove_file(log_path).await.ok();
        }
        Ok(())
    }

    pub async fn run_in_bottle(
        &self,
        name: &BottleName,
        executable: &str,
        args: &[String],
        extra_env: Option<HashMap<String, String>>,
    ) -> Result<i32> {
        let prefix_path = self.bottle_path(name);
        if !prefix_path.exists() {
            bail!("bottle {} does not exist", name.as_str());
        }

        let log_path = self.log_path(name);
        let log_file = OpenOptions::new()
            .create(true)
            .append(true)
            .open(&log_path)
            .await
            .with_context(|| format!("unable to open log file {}", log_path.display()))?;
        let log_writer = Arc::new(Mutex::new(log_file));

        let mut cmd = Command::new("arch");
        cmd.arg("-x86_64");
        cmd.arg(self.runtime.wine64());
        cmd.arg(executable);
        for arg in args {
            cmd.arg(arg);
        }
        cmd.env("WINEPREFIX", &prefix_path);
        cmd.env("WINEDEBUG", "-all");
        for (key, value) in self.runtime.default_environment() {
            cmd.env(key, value);
        }
        if let Some(env) = extra_env {
            for (key, value) in env {
                cmd.env(key, value);
            }
        }
        cmd.stdout(std::process::Stdio::piped());
        cmd.stderr(std::process::Stdio::piped());

        let mut child = cmd.spawn().context("failed to spawn wine process")?;
        let stdout = child.stdout.take();
        let stderr = child.stderr.take();

        let mut tasks = Vec::new();
        if let Some(stream) = stdout {
            tasks.push(tokio::spawn(pipe_stream(stream, log_writer.clone(), "stdout".into())));
        }
        if let Some(stream) = stderr {
            tasks.push(tokio::spawn(pipe_stream(stream, log_writer.clone(), "stderr".into())));
        }

        let status = child.wait().await?;
        for task in tasks {
            task.await??;
        }

        Ok(status.code().unwrap_or_default())
    }

    async fn bootstrap_prefix(&self, prefix_path: &Path) -> Result<()> {
        let mut cmd = Command::new("arch");
        cmd.arg("-x86_64");
        cmd.arg(self.runtime.wineboot());
        cmd.env("WINEPREFIX", prefix_path);
        cmd.env("WINEDEBUG", "-all");
        for (key, value) in self.runtime.default_environment() {
            cmd.env(key, value);
        }
        cmd.stdout(std::process::Stdio::null());
        cmd.stderr(std::process::Stdio::piped());

        let mut child = cmd.spawn().context("unable to launch wineboot")?;
        if let Some(stderr) = child.stderr.take() {
            let log_path = self.logs_dir.join("bootstrap.log");
            let file = OpenOptions::new().create(true).append(true).open(log_path).await?;
            let writer = Arc::new(Mutex::new(file));
            let _ = pipe_stream(stderr, writer, "wineboot".into()).await;
        }

        let status = timeout(Duration::from_secs(120), child.wait())
            .await
            .context("wineboot timed out")??;
        if !status.success() {
            bail!("wineboot exited with {}", status);
        }
        Ok(())
    }
}

async fn pipe_stream<R>(stream: R, log: Arc<Mutex<tokio::fs::File>>, label: String) -> Result<()>
where
    R: tokio::io::AsyncRead + Unpin + Send + 'static,
{
    let mut reader = BufReader::new(stream).lines();
    while let Some(line) = reader.next_line().await? {
        let mut guard = log.lock().await;
        guard
            .write_all(format!("[{}] {}\n", label, line).as_bytes())
            .await?;
    }
    Ok(())
}

fn data_root() -> Result<PathBuf> {
    if let Some(dir) = dirs::data_dir() {
        let path = dir.join("SiliconAlloy");
        fs::create_dir_all(&path)?;
        Ok(path)
    } else if let Some(home) = home_dir() {
        let fallback = home.join("Library").join("Application Support").join("SiliconAlloy");
        fs::create_dir_all(&fallback)?;
        Ok(fallback)
    } else {
        Err(anyhow!("cannot locate a writable data directory for bottles"))
    }
}

#[cfg(test)]
mod tests {
    use super::BottleName;

    #[test]
    fn bottle_name_sanitizes() {
        let name = "My Fancy App";
        let parsed = name.parse::<BottleName>().unwrap();
        assert_eq!(parsed.as_str(), "my-fancy-app");
    }

    #[test]
    fn bottle_name_rejects_blank() {
        assert!("!!!".parse::<BottleName>().is_err());
    }
}

