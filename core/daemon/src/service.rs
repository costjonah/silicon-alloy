use std::path::PathBuf;
use std::sync::Arc;

use anyhow::{anyhow, Context, Result};
use serde::Deserialize;
use serde_json::{json, Value};
use silicon_alloy_shared::recipes::{default_recipe_root, find_recipe, load_all, Recipe, RecipeStep};
use silicon_alloy_shared::{discover_runtimes, runtime_root, BottleRecord, BottleStore, RuntimeDescriptor, WineRuntime};
use tokio::process::Command;
use tracing::{info, warn};
use uuid::Uuid;

use crate::rpc::RpcRequest;

#[derive(Clone)]
pub struct DaemonService {
    state: Arc<State>,
}

struct State {
    bottles: BottleStore,
    runtime_dir: PathBuf,
    recipe_dir: PathBuf,
    runtimes: Vec<RuntimeDescriptor>,
}

impl DaemonService {
    pub async fn new() -> Result<Self> {
        let bottles = BottleStore::new()?;
        let runtime_dir = runtime_root()?;
        let recipe_dir = recipe_dir()?;
        let mut runtimes = discover_runtimes(&runtime_dir)?;
        if let Ok(extra) = std::env::var("SILICON_ALLOY_ARM64_WINE64") {
            let path = PathBuf::from(&extra);
            if path.exists() {
                runtimes.push(RuntimeDescriptor {
                    channel: "native-arm64".to_string(),
                    label: "wine arm64 (external)".to_string(),
                    version: "experimental".to_string(),
                    wine64_path: path,
                    notes: Some("provided via SILICON_ALLOY_ARM64_WINE64".to_string()),
                });
            }
        }
        if runtimes.is_empty() {
            tracing::warn!("no wine runtimes discovered under {}", runtime_dir.display());
        }
        Ok(Self {
            state: Arc::new(State {
                bottles,
                runtime_dir,
                recipe_dir,
                runtimes,
            }),
        })
    }

    pub async fn handle(&self, request: RpcRequest) -> Result<Value> {
        match request.method.as_str() {
            "service.ping" => Ok(json!({ "status": "ok" })),
            "service.info" => self.service_info().await,
            "runtime.list" => self.runtime_list().await,
            "bottle.list" => self.bottle_list().await,
            "bottle.create" => self.bottle_create(request.params).await,
            "bottle.delete" => self.bottle_delete(request.params).await,
            "bottle.run" => self.bottle_run(request.params).await,
            "recipe.list" => self.recipe_list().await,
            "recipe.apply" => self.recipe_apply(request.params).await,
            _ => Err(anyhow!("unknown method {}", request.method)),
        }
    }

    async fn service_info(&self) -> Result<Value> {
        Ok(json!({
            "version": env!("CARGO_PKG_VERSION"),
            "runtime_dir": self.state.runtime_dir,
            "bottle_root": self.state.bottles.root(),
            "runtimes": self.state.runtimes,
        }))
    }

    async fn runtime_list(&self) -> Result<Value> {
        Ok(json!({ "runtimes": self.state.runtimes }))
    }

    async fn recipe_list(&self) -> Result<Value> {
        let recipes = load_all(&self.state.recipe_dir)?;
        let summaries: Vec<Value> = recipes
            .into_iter()
            .map(|recipe| {
                json!({
                    "id": recipe.manifest.id,
                    "name": recipe.manifest.name,
                    "description": recipe.manifest.description,
                })
            })
            .collect();
        Ok(json!({ "recipes": summaries }))
    }

    async fn recipe_apply(&self, params: Value) -> Result<Value> {
        let input: RecipeApplyParams =
            serde_json::from_value(params).context("expected recipe.apply params { bottle_id, recipe_id }")?;
        let recipe = find_recipe(&self.state.recipe_dir, &input.recipe_id)?;
        self.apply_recipe(input.bottle_id, recipe).await
    }

    async fn bottle_list(&self) -> Result<Value> {
        let bottles = self.state.bottles.list().await?;
        Ok(json!({ "bottles": bottles }))
    }

    async fn bottle_create(&self, params: Value) -> Result<Value> {
        let input: BottleCreateParams = serde_json::from_value(params)
            .context("expected bottle.create params { name, wine_path, wine_version, wine_label }")?;
        let runtime = self.select_runtime(&input)?;
        let record = self.state.bottles.create(&input.name, runtime).await?;
        info!("created bottle {} ({})", record.name, record.id);
        Ok(json!({ "bottle": record }))
    }

    async fn bottle_delete(&self, params: Value) -> Result<Value> {
        let input: BottleDeleteParams =
            serde_json::from_value(params).context("expected bottle.delete params { id }")?;
        self.state.bottles.remove(input.id).await?;
        Ok(json!({ "deleted": input.id }))
    }

    async fn bottle_run(&self, params: Value) -> Result<Value> {
        let input: BottleRunParams =
            serde_json::from_value(params).context("expected bottle.run params { id, executable, args? }")?;
        let record = self.state.bottles.record(input.id).await?;
        let prefix = self.state.bottles.bottle_prefix(input.id);
        let mut args = vec![input.executable.to_string_lossy().to_string()];
        if let Some(rest) = input.args {
            args.extend(rest);
        }
        let status = run_wine_command(
            &record,
            &prefix,
            record.wine_runtime.wine64_path.clone(),
            args,
            &[],
        )
        .await?;
        Ok(json!({
            "exit_status": status.code(),
            "success": status.success(),
        }))
    }

    async fn apply_recipe(&self, bottle_id: Uuid, recipe: Recipe) -> Result<Value> {
        let mut record = self.state.bottles.record(bottle_id).await?;
        let prefix = self.state.bottles.bottle_prefix(bottle_id);
        for step in recipe.manifest.steps.iter() {
            match step {
                RecipeStep::Run { path, args } => {
                    let resolved = recipe.resource(path);
                    run_wine_command(
                        &record,
                        &prefix,
                        resolved,
                        args.clone(),
                        &[],
                    )
                    .await?;
                }
                RecipeStep::WaitForExit => {
                    tracing::info!("wait step implicitly satisfied (processes run synchronously)");
                }
                RecipeStep::WineCfg { version } => {
                    if let Some(version) = version {
                        record.environment.push((
                            "WINE_DEFAULT_VERSION".to_string(),
                            version.clone(),
                        ));
                    }
                    let winecfg_path = record
                        .wine_runtime
                        .wine64_path
                        .parent()
                        .map(|p| p.join("winecfg"))
                        .ok_or_else(|| anyhow!("wine runtime missing winecfg companion"))?;
                    run_wine_command(
                        &record,
                        &prefix,
                        winecfg_path,
                        vec![],
                        &[],
                    )
                    .await?;
                }
                RecipeStep::Env { variables } => {
                    for (key, value) in variables {
                        record
                            .environment
                            .retain(|(existing, _)| existing != key);
                        record.environment.push((key.clone(), value.clone()));
                    }
                }
            }
        }
        self.state.bottles.update_record(bottle_id, &record).await?;
        Ok(json!({ "applied": recipe.manifest.id }))
    }
}

fn default_wine_path(runtime_dir: &PathBuf, version: &str) -> PathBuf {
    runtime_dir
        .join(format!("wine-x86_64-{version}"))
        .join("bin")
        .join("wine64")
}

impl DaemonService {
    fn select_runtime(&self, input: &BottleCreateParams) -> Result<WineRuntime> {
        if let Some(path) = &input.wine_path {
            return Ok(WineRuntime {
                label: input
                    .wine_label
                    .clone()
                    .unwrap_or_else(|| format!("custom wine {}", input.wine_version)),
                wine64_path: path.clone(),
                version: input.wine_version.clone(),
                channel: input.channel.clone().or_else(|| Some("custom".to_string())),
            });
        }
        let channel = input.channel.clone().unwrap_or_else(|| "rossetta".to_string());
        if let Some(descriptor) = self
            .state
            .runtimes
            .iter()
            .find(|rt| rt.channel == channel && rt.version == input.wine_version)
        {
            return Ok(Self::descriptor_to_runtime(descriptor.clone(), input.wine_label.clone()));
        }
        if let Some(descriptor) = self
            .state
            .runtimes
            .iter()
            .find(|rt| rt.channel == channel)
        {
            return Ok(Self::descriptor_to_runtime(descriptor.clone(), input.wine_label.clone()));
        }
        let fallback = WineRuntime {
            label: input
                .wine_label
                .clone()
                .unwrap_or_else(|| format!("wine {}", input.wine_version)),
            wine64_path: default_wine_path(&self.state.runtime_dir, &input.wine_version),
            version: input.wine_version.clone(),
            channel: Some(channel),
        };
        Ok(fallback)
    }

    fn descriptor_to_runtime(descriptor: RuntimeDescriptor, override_label: Option<String>) -> WineRuntime {
        let mut runtime = descriptor.into_wine_runtime();
        if let Some(label) = override_label {
            runtime.label = label;
        }
        runtime
    }
}

#[derive(Debug, Deserialize)]
struct BottleCreateParams {
    name: String,
    wine_version: String,
    #[serde(default)]
    wine_label: Option<String>,
    #[serde(default)]
    wine_path: Option<PathBuf>,
    #[serde(default)]
    channel: Option<String>,
}

#[derive(Debug, Deserialize)]
struct BottleDeleteParams {
    id: Uuid,
}

#[derive(Debug, Deserialize)]
struct BottleRunParams {
    id: Uuid,
    executable: PathBuf,
    #[serde(default)]
    args: Option<Vec<String>>,
}

#[derive(Debug, Deserialize)]
struct RecipeApplyParams {
    bottle_id: Uuid,
    recipe_id: String,
}

fn recipe_dir() -> Result<PathBuf> {
    if let Ok(custom) = std::env::var("SILICON_ALLOY_RECIPES") {
        return Ok(PathBuf::from(custom));
    }
    default_recipe_root()
}

async fn run_wine_command(
    record: &BottleRecord,
    prefix: &PathBuf,
    command: PathBuf,
    args: Vec<String>,
    extra_env: &[(String, String)],
) -> Result<std::process::ExitStatus> {
    let mut cmd = Command::new("arch");
    cmd.arg("-x86_64")
        .arg(&command);
    cmd.args(&args);
    cmd.env("WINEPREFIX", prefix);
    for (k, v) in &record.environment {
        cmd.env(k, v);
    }
    for (k, v) in extra_env {
        cmd.env(k, v);
    }
    cmd.current_dir(prefix);
    let status = cmd.status().await?;
    if !status.success() {
        warn!(
            "wine command {:?} exited with {:?}",
            command,
            status.code()
        );
    }
    Ok(status)
}

