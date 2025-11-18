use anyhow::{Context, Result};
use serde_json::{json, Value};
use silicon_alloy_shared::daemon_socket_path;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::UnixStream;

pub struct RpcClient;

impl RpcClient {
    pub async fn call(method: &str, params: Value) -> Result<Value> {
        let socket = daemon_socket_path()?;
        let stream = UnixStream::connect(&socket)
            .await
            .with_context(|| format!("unable to connect to daemon at {:?}", socket))?;
        let (reader, mut writer) = stream.into_split();
        let mut reader = BufReader::new(reader);
        let request = json!({
            "id": 1,
            "method": method,
            "params": params,
        });
        let encoded = serde_json::to_vec(&request)?;
        writer.write_all(&encoded).await?;
        writer.write_all(b"\n").await?;
        writer.flush().await?;

        let mut line = String::new();
        reader.read_line(&mut line).await?;
        if line.is_empty() {
            anyhow::bail!("daemon closed connection without response");
        }
        let response: Value = serde_json::from_str(line.trim())?;
        if let Some(error) = response.get("error") {
            anyhow::bail!("daemon returned error: {}", error);
        }
        response
            .get("result")
            .cloned()
            .ok_or_else(|| anyhow::anyhow!("missing result field"))
    }
}

