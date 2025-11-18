use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use anyhow::{anyhow, Context, Result};
use directories::ProjectDirs;
use serde::{Deserialize, Serialize};
use tokio::fs;
use tokio::io::AsyncWriteExt;
use uuid::Uuid;

const BOTTLE_META: &str = "bottle.json";

pub mod recipes;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BottleRecord {
    pub id: Uuid,
    pub name: String,
    pub created_at: u64,
    pub wine_runtime: WineRuntime,
    pub environment: Vec<(String, String)>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WineRuntime {
    pub label: String,
    pub wine64_path: PathBuf,
    pub version: String,
    #[serde(default)]
    pub channel: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RuntimeDescriptor {
    pub channel: String,
    pub label: String,
    pub version: String,
    pub wine64_path: PathBuf,
    #[serde(default)]
    pub notes: Option<String>,
}

impl RuntimeDescriptor {
    pub fn into_wine_runtime(self) -> WineRuntime {
        WineRuntime {
            label: self.label,
            wine64_path: self.wine64_path,
            version: self.version,
            channel: Some(self.channel),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BottleList {
    pub bottles: Vec<BottleRecord>,
}

#[derive(Clone)]
pub struct BottleStore {
    root: PathBuf,
}

impl BottleStore {
    pub fn new() -> Result<Self> {
        let dirs = project_dirs()?;
        let root = dirs.data_dir().join("bottles");
        std::fs::create_dir_all(&root).context("failed to create bottle root")?;
        Ok(Self { root })
    }

    pub fn root(&self) -> &Path {
        &self.root
    }

    pub async fn list(&self) -> Result<Vec<BottleRecord>> {
        let mut bottles = Vec::new();
        let mut entries = fs::read_dir(&self.root).await?;
        while let Some(entry) = entries.next_entry().await? {
            let meta_path = entry.path().join(BOTTLE_META);
            if meta_path.exists() {
                let data = fs::read(&meta_path).await?;
                match serde_json::from_slice::<BottleRecord>(&data) {
                    Ok(record) => bottles.push(record),
                    Err(err) => {
                        tracing::warn!("ignored bottle {:?}: {}", meta_path, err);
                    }
                }
            }
        }
        bottles.sort_by(|a, b| a.name.cmp(&b.name));
        Ok(bottles)
    }

    pub async fn create(&self, name: &str, runtime: WineRuntime) -> Result<BottleRecord> {
        let id = Uuid::new_v4();
        let bottle_dir = self.root.join(id.to_string());
        fs::create_dir_all(&bottle_dir)
            .await
            .context("failed to create bottle directory")?;
        let prefix = bottle_dir.join("prefix");
        fs::create_dir_all(&prefix)
            .await
            .context("failed to create wine prefix directory")?;
        let record = BottleRecord {
            id,
            name: name.to_string(),
            created_at: unix_timestamp(),
            wine_runtime: runtime,
            environment: Vec::new(),
        };
        self.write_record(&bottle_dir, &record).await?;
        Ok(record)
    }

    pub async fn remove(&self, id: Uuid) -> Result<()> {
        let dir = self.root.join(id.to_string());
        if dir.exists() {
            fs::remove_dir_all(&dir)
                .await
                .with_context(|| format!("failed to remove bottle {id}"))?;
        } else {
            return Err(anyhow!("bottle {id} not found"));
        }
        Ok(())
    }

    pub async fn record(&self, id: Uuid) -> Result<BottleRecord> {
        let dir = self.root.join(id.to_string());
        let data = fs::read(dir.join(BOTTLE_META))
            .await
            .with_context(|| format!("failed to read bottle metadata for {id}"))?;
        Ok(serde_json::from_slice(&data)?)
    }

    pub async fn update_record(&self, id: Uuid, record: &BottleRecord) -> Result<()> {
        let dir = self.root.join(id.to_string());
        if !dir.exists() {
            return Err(anyhow!("bottle {id} not found"));
        }
        self.write_record(&dir, record).await
    }

    pub fn bottle_prefix(&self, id: Uuid) -> PathBuf {
        self.root.join(id.to_string()).join("prefix")
    }

    async fn write_record(&self, dir: &Path, record: &BottleRecord) -> Result<()> {
        let meta_path = dir.join(BOTTLE_META);
        let mut file = fs::File::create(&meta_path)
            .await
            .with_context(|| format!("failed to write {:?}", meta_path))?;
        let data = serde_json::to_vec_pretty(record)?;
        file.write_all(&data).await?;
        Ok(())
    }
}

pub fn project_dirs() -> Result<ProjectDirs> {
    ProjectDirs::from("com", "SiliconAlloy", "SiliconAlloy")
        .ok_or_else(|| anyhow!("unable to determine project directories"))
}

pub fn runtime_root() -> Result<PathBuf> {
    let dirs = project_dirs()?;
    let path = dirs.data_dir().join("runtime");
    std::fs::create_dir_all(&path)?;
    Ok(path)
}

pub fn daemon_socket_path() -> Result<PathBuf> {
    let dirs = project_dirs()?;
    let runtime_dir = dirs.runtime_dir().unwrap_or_else(|| dirs.data_dir());
    std::fs::create_dir_all(runtime_dir)?;
    Ok(runtime_dir.join("daemon.sock"))
}

pub fn discover_runtimes(root: &Path) -> Result<Vec<RuntimeDescriptor>> {
    if !root.exists() {
        return Ok(vec![]);
    }
    let mut runtimes = Vec::new();
    /*
     * the tooling depends on folder names to scope runtimes: wine-<arch>-<version>.
     * we parse that shape to keep discovery lightweight and deterministic, which is
     * important for cache hits and upgrade heuristics. if we ever move to manifests,
     * make sure this stays backward compatible
     */
    for entry in std::fs::read_dir(root)? {
        let entry = entry?;
        if !entry.file_type()?.is_dir() {
            continue;
        }
        let name = match entry.file_name().into_string() {
            Ok(name) => name,
            Err(_) => continue,
        };
        let parts: Vec<_> = name.split('-').collect();
        if parts.len() < 3 || parts[0] != "wine" {
            continue;
        }
        let arch = parts[1];
        let version = parts[2..].join("-");
        let channel = match arch {
            "x86_64" => "rossetta".to_string(),
            "arm64" => "native-arm64".to_string(),
            other => format!("custom-{other}"),
        };
        let wine64_path = entry.path().join("bin").join("wine64");
        if !wine64_path.exists() {
            continue;
        }
        runtimes.push(RuntimeDescriptor {
            channel,
            label: format!("wine {arch} {version}"),
            version,
            wine64_path,
            notes: None,
        });
    }
    runtimes.sort_by(|a, b| a.label.cmp(&b.label));
    Ok(runtimes)
}

fn unix_timestamp() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or_default()
}

