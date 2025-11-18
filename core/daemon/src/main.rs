mod rpc;
mod service;

use anyhow::Result;
use once_cell::sync::OnceLock;
use rpc::{RpcRequest, RpcResponse};
use service::DaemonService;
use silicon_alloy_shared::{daemon_socket_path, project_dirs};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::UnixListener;
use tracing::{error, info};
use tracing_appender::non_blocking::WorkerGuard;
use tracing_subscriber::{fmt, prelude::*, EnvFilter};

static LOG_GUARD: OnceLock<WorkerGuard> = OnceLock::new();

#[tokio::main]
async fn main() -> Result<()> {
    setup_tracing()?;
    let socket_path = socket_path()?;
    info!("starting daemon on {}", socket_path.display());
    if socket_path.exists() {
        std::fs::remove_file(&socket_path)?;
    }
    let listener = UnixListener::bind(&socket_path)?;
    let service = DaemonService::new().await?;
    loop {
        let (stream, _) = listener.accept().await?;
        let svc = service.clone();
        tokio::spawn(async move {
            if let Err(err) = handle_connection(svc, stream).await {
                error!("connection failed: {err:?}");
            }
        });
    }
}

fn setup_tracing() -> Result<()> {
    let dirs = project_dirs()?;
    let log_dir = dirs.data_dir().join("logs");
    std::fs::create_dir_all(&log_dir)?;

    let file_appender = tracing_appender::rolling::daily(&log_dir, "daemon.log");
    let (non_blocking, guard) = tracing_appender::non_blocking(file_appender);
    let _ = LOG_GUARD.set(guard);

    let env_filter = std::env::var("SILICON_ALLOY_LOG")
        .ok()
        .and_then(|value| EnvFilter::try_new(value).ok())
        .unwrap_or_else(|| EnvFilter::new("info"));

    let registry = tracing_subscriber::registry()
        .with(env_filter)
        .with(fmt::layer())
        .with(fmt::layer().with_ansi(false).with_writer(non_blocking));

    let _ = registry.try_init();
    Ok(())
}

fn socket_path() -> Result<std::path::PathBuf> {
    daemon_socket_path()
}

async fn handle_connection(service: DaemonService, stream: tokio::net::UnixStream) -> Result<()> {
    let (reader, mut writer) = stream.into_split();
    let mut reader = BufReader::new(reader);
    let mut line = String::new();
    loop {
        line.clear();
        let bytes = reader.read_line(&mut line).await?;
        if bytes == 0 {
            break;
        }
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        let request: RpcRequest = match serde_json::from_str(trimmed) {
            Ok(req) => req,
            Err(err) => {
                let response = RpcResponse::error(None, -32700, format!("invalid json: {err}"));
                writer.write_all(response.to_json().as_bytes()).await?;
                writer.write_all(b"\n").await?;
                continue;
            }
        };
        let response = match service.handle(request.clone()).await {
            Ok(value) => RpcResponse::result(request.id.clone(), value),
            Err(err) => RpcResponse::error(Some(request.id.clone()), -32000, format!("{err:#}")),
        };
        writer.write_all(response.to_json().as_bytes()).await?;
        writer.write_all(b"\n").await?;
        writer.flush().await?;
    }
    Ok(())
}

