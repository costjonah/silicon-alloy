use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};

use anyhow::{anyhow, Context, Result};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RecipeManifest {
    pub id: String,
    pub name: String,
    #[serde(default)]
    pub description: Option<String>,
    pub steps: Vec<RecipeStep>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum RecipeStep {
    Run { path: PathBuf, #[serde(default)] args: Vec<String> },
    WaitForExit,
    WineCfg { #[serde(default)] version: Option<String> },
    Env { variables: Vec<(String, String)> },
    Copy { from: PathBuf, to: PathBuf },
}

#[derive(Debug, Clone)]
pub struct Recipe {
    pub manifest: RecipeManifest,
    pub base_dir: PathBuf,
}

impl Recipe {
    pub fn resource(&self, relative: &Path) -> PathBuf {
        if relative.is_absolute() {
            relative.to_path_buf()
        } else {
            self.base_dir.join("resources").join(relative)
        }
    }
}

pub fn load_all(dir: &Path) -> Result<Vec<Recipe>> {
    if !dir.exists() {
        return Ok(vec![]);
    }
    let mut recipes = Vec::new();
    for entry in fs::read_dir(dir)? {
        let entry = entry?;
        if entry.file_type()?.is_dir() {
            let manifest_path = entry.path().join("recipe.yaml");
            if manifest_path.exists() {
                recipes.push(load_recipe(&manifest_path)?);
            }
        } else if entry.path().extension().and_then(|s| s.to_str()) == Some("yaml") {
            recipes.push(load_recipe(&entry.path())?);
        }
    }
    recipes.sort_by(|a, b| a.manifest.name.cmp(&b.manifest.name));
    Ok(recipes)
}

pub fn find_recipe(dir: &Path, id: &str) -> Result<Recipe> {
    let recipes = load_all(dir)?;
    recipes
        .into_iter()
        .find(|recipe| recipe.manifest.id == id)
        .ok_or_else(|| anyhow!("recipe {id} not found in {}", dir.display()))
}

pub fn load_recipe(path: &Path) -> Result<Recipe> {
    let data = fs::read_to_string(path)
        .with_context(|| format!("failed to read recipe manifest at {}", path.display()))?;
    let raw: RecipeManifestRaw = serde_yaml::from_str(&data)
        .with_context(|| format!("invalid recipe yaml {}", path.display()))?;
    let manifest = raw.normalize()?;
    Ok(Recipe {
        manifest,
        base_dir: path
            .parent()
            .map(|p| p.to_path_buf())
            .unwrap_or_else(|| PathBuf::from(".")),
    })
}

pub fn default_recipe_root() -> Result<PathBuf> {
    let dirs = crate::project_dirs()?;
    let path = dirs.data_dir().join("recipes");
    std::fs::create_dir_all(&path)?;
    Ok(path)
}

#[derive(Debug, Deserialize)]
struct RecipeManifestRaw {
    id: String,
    name: String,
    #[serde(default)]
    description: Option<String>,
    steps: Vec<RecipeStepRaw>,
}

impl RecipeManifestRaw {
    fn normalize(self) -> Result<RecipeManifest> {
        let steps = self
            .steps
            .into_iter()
            .map(RecipeStepRaw::normalize)
            .collect::<Result<Vec<_>>>()?;
        Ok(RecipeManifest {
            id: self.id,
            name: self.name,
            description: self.description,
            steps,
        })
    }
}

#[derive(Debug, Deserialize)]
#[serde(untagged)]
enum RecipeStepRaw {
    RunString { run: String },
    RunObject { run: RunParams },
    Wait { wait_for_exit: bool },
    WineCfg { winecfg: WineCfgParams },
    Env { env: BTreeMap<String, String> },
    Copy { copy: CopyParams },
}

impl RecipeStepRaw {
    fn normalize(self) -> Result<RecipeStep> {
        match self {
            RecipeStepRaw::RunString { run } => Ok(RecipeStep::Run {
                path: PathBuf::from(run),
                args: vec![],
            }),
            RecipeStepRaw::RunObject { run } => Ok(RecipeStep::Run {
                path: PathBuf::from(
                    run.command
                        .or(run.file)
                        .ok_or_else(|| anyhow!("run step missing command"))?,
                ),
                args: run.args.unwrap_or_default(),
            }),
            RecipeStepRaw::Wait { wait_for_exit } => {
                if wait_for_exit {
                    Ok(RecipeStep::WaitForExit)
                } else {
                    Err(anyhow!("wait_for_exit must be true when specified"))
                }
            }
            RecipeStepRaw::WineCfg { winecfg } => Ok(RecipeStep::WineCfg { version: winecfg.version }),
            RecipeStepRaw::Env { env } => Ok(RecipeStep::Env {
                variables: env.into_iter().collect(),
            }),
            RecipeStepRaw::Copy { copy } => Ok(RecipeStep::Copy {
                from: copy.from,
                to: copy.to,
            }),
        }
    }
}

#[derive(Debug, Deserialize)]
struct RunParams {
    command: Option<String>,
    #[serde(alias = "path")]
    file: Option<String>,
    #[serde(default)]
    args: Option<Vec<String>>,
}

#[derive(Debug, Deserialize)]
struct WineCfgParams {
    #[serde(default)]
    version: Option<String>,
}

#[derive(Debug, Deserialize)]
struct CopyParams {
    from: PathBuf,
    to: PathBuf,
}

