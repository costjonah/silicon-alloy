use crate::bottle::{BottleManager, BottleName};
use anyhow::{anyhow, Context, Result};
use serde::Deserialize;
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use tokio::fs;

#[derive(Debug, Deserialize, Clone)]
pub struct Recipe {
    pub id: String,
    pub name: String,
    #[serde(default)]
    pub description: Option<String>,
    #[serde(default)]
    pub runtime: Option<String>,
    #[serde(default)]
    pub steps: Vec<RecipeStep>,
}

#[derive(Debug, Deserialize, Clone)]
#[serde(untagged)]
pub enum RecipeStep {
    Run {
        run: RecipeRun,
    },
    RunSimple {
        run: String,
    },
    Env {
        env: HashMap<String, String>,
    },
    Winecfg {
        winecfg: RecipeWinecfg,
    },
    Note {
        note: String,
    },
}

#[derive(Debug, Deserialize, Clone)]
pub struct RecipeRun {
    pub command: String,
    #[serde(default)]
    pub args: Vec<String>,
}

#[derive(Debug, Deserialize, Clone)]
pub struct RecipeWinecfg {
    #[serde(default)]
    pub version: Option<String>,
}

pub struct RecipeCatalog {
    root: PathBuf,
}

impl RecipeCatalog {
    pub fn discover() -> Self {
        if let Ok(env) = std::env::var("SILICON_ALLOY_RECIPES") {
            return Self {
                root: PathBuf::from(env),
            };
        }
        let repo_path = PathBuf::from("recipes");
        if repo_path.exists() {
            return Self { root: repo_path };
        }
        let default = dirs::data_dir()
            .unwrap_or_else(|| PathBuf::from("/Library/Application Support/SiliconAlloy"))
            .join("recipes");
        Self { root: default }
    }

    pub fn with_root<P: AsRef<Path>>(root: P) -> Self {
        Self {
            root: root.as_ref().to_path_buf(),
        }
    }

    pub async fn list(&self) -> Result<Vec<Recipe>> {
        let mut items = Vec::new();
        let mut entries = fs::read_dir(&self.root)
            .await
            .with_context(|| format!("reading recipes from {}", self.root.display()))?;

        while let Some(entry) = entries.next_entry().await? {
            let path = entry.path();
            if !path.is_file() {
                continue;
            }
            if let Some(ext) = path.extension() {
                if ext != "yml" && ext != "yaml" {
                    continue;
                }
            } else {
                continue;
            }
            if let Ok(recipe) = load_recipe(&path).await {
                items.push(recipe);
            }
        }

        items.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()));
        Ok(items)
    }

    pub async fn load(&self, id: &str) -> Result<Recipe> {
        let mut path = self.root.join(format!("{id}.yml"));
        if !path.exists() {
            path = self.root.join(format!("{id}.yaml"));
        }
        if !path.exists() {
            return Err(anyhow!("recipe {id} not found in {}", self.root.display()));
        }
        load_recipe(&path).await
    }
}

async fn load_recipe(path: &Path) -> Result<Recipe> {
    let contents = fs::read_to_string(path)
        .await
        .with_context(|| format!("reading recipe {}", path.display()))?;
    let mut recipe: Recipe = serde_yaml::from_str(&contents)
        .with_context(|| format!("parsing recipe {}", path.display()))?;

    // normalize simple run steps
    for step in &mut recipe.steps {
        if let RecipeStep::RunSimple { run } = step.clone() {
            *step = RecipeStep::Run {
                run: RecipeRun {
                    command: run,
                    args: Vec::new(),
                },
            };
        }
    }
    Ok(recipe)
}

pub struct RecipeExecutor<'a> {
    manager: &'a BottleManager,
    bottle: BottleName,
    env: HashMap<String, String>,
}

impl<'a> RecipeExecutor<'a> {
    pub fn new(manager: &'a BottleManager, bottle: BottleName) -> Self {
        Self {
            manager,
            bottle,
            env: HashMap::new(),
        }
    }

    pub async fn apply(&mut self, recipe: &Recipe) -> Result<()> {
        for step in &recipe.steps {
            match step {
                RecipeStep::Run { run } => {
                    self.run_command(run).await?;
                }
                RecipeStep::Env { env } => {
                    for (key, value) in env {
                        self.env.insert(key.clone(), value.clone());
                    }
                }
                RecipeStep::Winecfg { winecfg } => {
                    self.configure_wine(winecfg).await?;
                }
                RecipeStep::Note { note } => {
                    eprintln!("[recipe] note: {note}");
                }
                RecipeStep::RunSimple { .. } => {
                    // already normalized above
                }
            }
        }
        Ok(())
    }

    async fn run_command(&self, run: &RecipeRun) -> Result<()> {
        let exit = self
            .manager
            .run_in_bottle(
                &self.bottle,
                &run.command,
                &run.args,
                Some(self.env.clone()),
            )
            .await?;
        if exit != 0 {
            return Err(anyhow!(
                "command {} exited with code {}",
                run.command,
                exit
            ));
        }
        Ok(())
    }

    async fn configure_wine(&self, winecfg: &RecipeWinecfg) -> Result<()> {
        let mut args = Vec::new();
        if let Some(version) = &winecfg.version {
            args.push("-v".to_string());
            args.push(version.clone());
        }
        let mut command = tokio::process::Command::new("arch");
        command.arg("-x86_64");
        command.arg(self.manager.runtime().winecfg());
        for arg in &args {
            command.arg(arg);
        }
        command.env(
            "WINEPREFIX",
            self.manager.bottle_prefix(&self.bottle),
        );
        command.env("WINEDEBUG", "-all");
        for (key, value) in self.manager.runtime().default_environment() {
            command.env(key, value);
        }
        for (key, value) in &self.env {
            command.env(key, value);
        }
        let status = command.status().await?;
        if !status.success() {
            return Err(anyhow!("winecfg exited with status {:?}", status.code()));
        }
        Ok(())
    }
}

