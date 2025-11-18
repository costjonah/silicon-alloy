mod rpc;
mod service;

use anyhow::Result;
use rpc::{RpcRequest, RpcResponse};
use service::DaemonService;
use silicon_alloy_shared::daemon_socket_path;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::UnixListener;
use tracing::{error, info};

#[tokio::main]
async fn main() -> Result<()> {
    setup_tracing();
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

fn setup_tracing() {
    let _ = tracing_subscriber::fmt()
        .with_env_filter("info")
        .try_init();
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

