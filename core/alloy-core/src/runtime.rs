use anyhow::{Context, Result};
use anyhow::bail;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct RuntimeMetadata {
    pub version: String,
    pub arch: String,
    pub built_at: Option<String>,
    pub sdk_path: Option<String>,
    pub sdk_version: Option<String>,
    pub min_macos: Option<String>,
}

#[derive(Clone, Debug)]
pub struct RuntimeLocator {
    root: PathBuf,
    metadata: RuntimeMetadata,
}

impl RuntimeLocator {
    pub fn detect() -> Result<Self> {
        if let Ok(path) = std::env::var("SILICON_ALLOY_RUNTIME_DIR") {
            return Self::with_root(PathBuf::from(path));
        }

        let system_path = PathBuf::from("/Library/SiliconAlloy/runtime");
        if system_path.exists() {
            return Self::with_root(system_path);
        }

        let dev_path = PathBuf::from("runtime/build/dist");
        if dev_path.exists() {
            let mut entries = fs::read_dir(&dev_path)?
                .flatten()
                .filter(|entry| entry.path().is_dir())
                .collect::<Vec<_>>();
            entries.sort_by_key(|entry| entry.file_name());
            if let Some(entry) = entries.pop() {
                return Self::with_root(entry.path());
            }
        }

        anyhow::bail!(
            "unable to locate a wine runtime. set SILICON_ALLOY_RUNTIME_DIR to the dist folder you built."
        );
    }

    pub fn with_root(root: PathBuf) -> Result<Self> {
        if !root.exists() {
            anyhow::bail!("runtime path {} does not exist", root.display());
        }

        let metadata = read_metadata(&root)?;
        Ok(Self { root, metadata })
    }

    pub fn root(&self) -> &Path {
        &self.root
    }

    pub fn metadata(&self) -> &RuntimeMetadata {
        &self.metadata
    }

    pub fn wine64(&self) -> PathBuf {
        self.root.join("bin").join("wine64")
    }

    pub fn wineboot(&self) -> PathBuf {
        self.root.join("bin").join("wineboot")
    }

    pub fn winecfg(&self) -> PathBuf {
        self.root.join("bin").join("winecfg")
    }

    pub fn default_environment(&self) -> HashMap<String, String> {
        let mut env = HashMap::new();
        env.insert(
            "DYLD_FALLBACK_LIBRARY_PATH".into(),
            self.root.join("lib").display().to_string(),
        );
        env
    }
}

fn read_metadata(root: &Path) -> Result<RuntimeMetadata> {
    let metadata_path = root.join("share").join("silicon-alloy").join("BUILDINFO");
    if !metadata_path.exists() {
        anyhow::bail!(
            "runtime at {} is missing BUILDINFO metadata",
            root.display()
        );
    }
    let contents = fs::read_to_string(&metadata_path)
        .with_context(|| format!("failed to read {}", metadata_path.display()))?;
    let mut version = None;
    let mut arch = None;
    let mut built_at = None;
    let mut sdk_path = None;
    let mut sdk_version = None;
    let mut min_macos = None;

    for line in contents.lines() {
        if let Some(rest) = line.strip_prefix("version=") {
            version = Some(rest.trim().to_string());
        } else if let Some(rest) = line.strip_prefix("arch=") {
            arch = Some(rest.trim().to_string());
        } else if let Some(rest) = line.strip_prefix("built_at=") {
            built_at = Some(rest.trim().to_string());
        } else if let Some(rest) = line.strip_prefix("sdk_path=") {
            let value = rest.trim();
            if !value.is_empty() {
                sdk_path = Some(value.to_string());
            }
        } else if let Some(rest) = line.strip_prefix("sdk_version=") {
            let value = rest.trim();
            if !value.is_empty() {
                sdk_version = Some(value.to_string());
            }
        } else if let Some(rest) = line.strip_prefix("min_macos=") {
            let value = rest.trim();
            if !value.is_empty() {
                min_macos = Some(value.to_string());
            }
        }
    }

    Ok(RuntimeMetadata {
        version: version.unwrap_or_else(|| "unknown".into()),
        arch: arch.unwrap_or_else(|| "unknown".into()),
        built_at,
        sdk_path,
        sdk_version,
        min_macos,
    })
}

