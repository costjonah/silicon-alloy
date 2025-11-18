use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::sync::Arc;

use anyhow::{anyhow, Context, Result};
use directories::UserDirs;
use serde::Deserialize;
use serde_json::{json, Value};
use silicon_alloy_shared::recipes::{default_recipe_root, find_recipe, load_all, Recipe, RecipeStep};
use silicon_alloy_shared::{
    discover_runtimes, runtime_root, BottleRecord, BottleStore, RuntimeDescriptor, WineRuntime,
};
use tokio::fs;
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
            "shortcut.create" => self.shortcut_create(request.params).await,
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

    async fn shortcut_create(&self, params: Value) -> Result<Value> {
        let input: ShortcutCreateParams = serde_json::from_value(params)
            .context("expected shortcut.create params { bottle_id, name, executable, destination? }")?;
        let record = self.state.bottles.record(input.bottle_id).await?;
        let prefix = self.state.bottles.bottle_prefix(input.bottle_id);
        let destination = match input.destination.clone() {
            Some(path) => path,
            None => default_shortcut_dir()?,
        };
        fs::create_dir_all(&destination).await?;
        let shortcut_path = destination.join(format!("{}.app", sanitize_name(&input.name)));
        create_shortcut_bundle(&shortcut_path, &record, &prefix, &input).await?;
        info!(
            "created shortcut {} for bottle {} ({})",
            shortcut_path.display(),
            record.name,
            record.id
        );
        Ok(json!({ "shortcut": shortcut_path }))
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
                RecipeStep::Copy { from, to } => {
                    let source = recipe.resource(from);
                    if !source.exists() {
                        return Err(anyhow!(
                            "recipe resource {:?} is missing",
                            source
                        ));
                    }
                    let destination = prefix.join(to);
                    if let Some(parent) = destination.parent() {
                        fs::create_dir_all(parent).await?;
                    }
                    fs::copy(&source, &destination).await?;
                }
            }
        }
        self.state.bottles.update_record(bottle_id, &record).await?;
        Ok(json!({ "applied": recipe.manifest.id }))
    }
}

async fn create_shortcut_bundle(
    shortcut_path: &Path,
    record: &BottleRecord,
    prefix: &Path,
    params: &ShortcutCreateParams,
) -> Result<()> {
    if fs::metadata(shortcut_path).await.is_ok() {
        fs::remove_dir_all(shortcut_path).await?;
    }

    let contents_dir = shortcut_path.join("Contents");
    let macos_dir = contents_dir.join("MacOS");
    let resources_dir = contents_dir.join("Resources");

    fs::create_dir_all(&macos_dir).await?;
    fs::create_dir_all(&resources_dir).await?;

    let info_plist = contents_dir.join("Info.plist");
    let plist = shortcut_info_plist(&params.name, record.id);
    fs::write(&info_plist, plist).await?;

    let script_path = macos_dir.join("launch");
    let script = shortcut_launcher_script(record, prefix, params);
    fs::write(&script_path, script).await?;
    let perms = std::fs::Permissions::from_mode(0o755);
    fs::set_permissions(&script_path, perms).await?;

    Ok(())
}

fn shortcut_info_plist(name: &str, id: Uuid) -> String {
    format!(
        r#"<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>launch</string>
    <key>CFBundleIdentifier</key>
    <string>com.siliconalloy.shortcut.{id}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>{name}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
</dict>
</plist>
"#
    )
}

fn shortcut_launcher_script(
    record: &BottleRecord,
    prefix: &Path,
    params: &ShortcutCreateParams,
) -> String {
    let wine_path = record.wine_runtime.wine64_path.to_string_lossy();
    let prefix_path = prefix.to_string_lossy();
    let executable = &params.executable;
    let mut script = String::from("#!/bin/zsh\nset -euo pipefail\n\n");
    script.push_str(&format!("export WINEPREFIX={}\n", shell_quote(&prefix_path)));
    for (key, value) in &record.environment {
        script.push_str(&format!("export {}={}\n", key, shell_quote(value)));
    }
    script.push_str("cd \"$WINEPREFIX\"\n");
    script.push_str(&format!(
        "exec arch -x86_64 {} {} \"$@\"\n",
        shell_quote(&wine_path),
        shell_quote(executable)
    ));
    script
}

fn sanitize_name(name: &str) -> String {
    let mut sanitized = String::with_capacity(name.len());
    for ch in name.chars() {
        if ch.is_alphanumeric() || ch == ' ' || ch == '-' || ch == '_' {
            sanitized.push(ch);
        } else {
            sanitized.push('_');
        }
    }
    let trimmed = sanitized.trim().to_string();
    if trimmed.is_empty() {
        "Windows App".to_string()
    } else {
        trimmed
    }
}

fn shell_quote(value: &str) -> String {
    if value.is_empty() {
        return "''".to_string();
    }
    if !value.contains('\'') {
        format!("'{}'", value)
    } else {
        format!("'{}'", value.replace('\'', "'\"'\"'"))
    }
}

fn default_shortcut_dir() -> Result<PathBuf> {
    let user_dirs = UserDirs::new().ok_or_else(|| anyhow!("unable to resolve user directories"))?;
    let home = user_dirs.home_dir();
    Ok(home.join("Applications").join("Silicon Alloy"))
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

#[derive(Debug, Deserialize)]
struct ShortcutCreateParams {
    bottle_id: Uuid,
    name: String,
    executable: String,
    #[serde(default)]
    destination: Option<PathBuf>,
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
    /*
     * we shell out through `arch -x86_64` to make sure apple's translator is used,
     * so rosetta reliably fronts every wine invocation. apple's
     * translator actually kicks in, doing it here means the env we curate for the bottle is exactly what wine sees,
     * and the exit status we bubble up is authoritative. the synchronous wait keeps
     * state updates deterministic for the caller
    */
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

