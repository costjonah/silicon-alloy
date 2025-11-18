use alloy_core::{
    BottleManager, BottleName, DaemonCommand, DaemonRequest, DaemonResponse, RecipeCatalog,
    RecipeExecutor, RuntimeLocator,
};
use anyhow::{Context, Result};
use serde_json::json;
use std::path::{Path, PathBuf};
use std::str::FromStr;
use std::sync::Arc;
use tokio::io::{AsyncBufReadExt, AsyncWrite, AsyncWriteExt, BufReader};
use tokio::net::{UnixListener, UnixStream};

#[tokio::main]
async fn main() -> Result<()> {
    let config = Config::from_env()?;
    if let Some(parent) = config.socket_path.parent() {
        tokio::fs::create_dir_all(parent)
            .await
            .with_context(|| format!("unable to create socket directory {}", parent.display()))?;
    }

    if config.socket_path.exists() {
        tokio::fs::remove_file(&config.socket_path).await.ok();
    }

    let runtime = match &config.runtime_dir {
        Some(path) => RuntimeLocator::with_root(path.clone())?,
        None => RuntimeLocator::detect()?,
    };
    let manager = Arc::new(BottleManager::new(runtime)?);

    let listener = UnixListener::bind(&config.socket_path)
        .with_context(|| format!("failed to bind {}", config.socket_path.display()))?;
    eprintln!(
        "[alloy-daemon] listening on {}",
        config.socket_path.display()
    );

    loop {
        let (stream, _) = listener.accept().await?;
        let manager = manager.clone();
        tokio::spawn(async move {
            if let Err(err) = handle_client(stream, manager).await {
                eprintln!("[alloy-daemon] client error: {err:?}");
            }
        });
    }
}

#[derive(Debug)]
struct Config {
    socket_path: PathBuf,
    runtime_dir: Option<PathBuf>,
}

impl Config {
    fn from_env() -> Result<Self> {
        let socket_path = std::env::var("SILICON_ALLOY_SOCKET")
            .map(PathBuf::from)
            .unwrap_or_else(|_| default_socket_path());

        let runtime_dir = std::env::var("SILICON_ALLOY_RUNTIME_DIR")
            .ok()
            .map(PathBuf::from);

        Ok(Self {
            socket_path,
            runtime_dir,
        })
    }
}

fn default_socket_path() -> PathBuf {
    let base = dirs::runtime_dir()
        .or_else(|| dirs::data_dir())
        .unwrap_or_else(|| PathBuf::from("/tmp"));
    base.join("silicon-alloy").join("daemon.sock")
}

async fn handle_client(stream: UnixStream, manager: Arc<BottleManager>) -> Result<()> {
    let (reader, mut writer) = stream.into_split();
    let mut reader = BufReader::new(reader).lines();

    while let Some(line) = reader.next_line().await? {
        if line.trim().is_empty() {
            continue;
        }

        let request: DaemonRequest = match serde_json::from_str(&line) {
            Ok(req) => req,
            Err(err) => {
                let response = DaemonResponse::error(uuid::Uuid::new_v4(), err.to_string());
                send_response(&mut writer, &response).await?;
                continue;
            }
        };

        let response = handle_request(manager.clone(), request).await;
        send_response(&mut writer, &response).await?;
    }
    Ok(())
}

async fn send_response<W>(writer: &mut W, response: &DaemonResponse) -> Result<()>
where
    W: AsyncWrite + Unpin,
{
    let payload = serde_json::to_vec(response)?;
    writer.write_all(&payload).await?;
    writer.write_all(b"\n").await?;
    writer.flush().await?;
    Ok(())
}

async fn handle_request(manager: Arc<BottleManager>, request: DaemonRequest) -> DaemonResponse {
    match request.command {
        DaemonCommand::Ping => DaemonResponse::empty(request.id),
        DaemonCommand::List => match manager.list_bottles().await {
            Ok(bottles) => DaemonResponse::ok(request.id, json!(bottles)),
            Err(err) => DaemonResponse::error(request.id, err.to_string()),
        },
        DaemonCommand::Create { name } => match BottleName::from_str(&name) {
            Ok(parsed) => match manager.create_bottle(&parsed).await {
                Ok(metadata) => DaemonResponse::ok(request.id, json!(metadata)),
                Err(err) => DaemonResponse::error(request.id, err.to_string()),
            },
            Err(err) => DaemonResponse::error(request.id, err.to_string()),
        },
        DaemonCommand::Destroy { name } => match BottleName::from_str(&name) {
            Ok(parsed) => match manager.destroy_bottle(&parsed).await {
                Ok(_) => DaemonResponse::empty(request.id),
                Err(err) => DaemonResponse::error(request.id, err.to_string()),
            },
            Err(err) => DaemonResponse::error(request.id, err.to_string()),
        },
        DaemonCommand::Run {
            name,
            executable,
            args,
            env,
        } => match BottleName::from_str(&name) {
            Ok(parsed) => match manager.run_in_bottle(&parsed, &executable, &args, env).await {
                Ok(code) => DaemonResponse::ok(request.id, json!({ "exit_code": code })),
                Err(err) => DaemonResponse::error(request.id, err.to_string()),
            },
            Err(err) => DaemonResponse::error(request.id, err.to_string()),
        },
        DaemonCommand::ListRecipes => {
            let catalog = RecipeCatalog::discover();
            match catalog.list().await {
                Ok(recipes) => DaemonResponse::ok(request.id, json!(recipes)),
                Err(err) => DaemonResponse::error(request.id, err.to_string()),
            }
        }
        DaemonCommand::ApplyRecipe { bottle, recipe } => match BottleName::from_str(&bottle) {
            Ok(parsed) => {
                let catalog = RecipeCatalog::discover();
                match catalog.load(&recipe).await {
                    Ok(def) => {
                        let mut executor = RecipeExecutor::new(&manager, parsed.clone());
                        match executor.apply(&def).await {
                            Ok(_) => DaemonResponse::ok(request.id, json!({ "applied": def.id })),
                            Err(err) => DaemonResponse::error(request.id, err.to_string()),
                        }
                    }
                    Err(err) => DaemonResponse::error(request.id, err.to_string()),
                }
            }
            Err(err) => DaemonResponse::error(request.id, err.to_string()),
        },
    }
}

