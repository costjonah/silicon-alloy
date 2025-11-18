use alloy_core::{DaemonCommand, DaemonRequest, DaemonResponse, DaemonStatus};
use anyhow::{Context, Result};
use clap::{Parser, Subcommand};
use std::path::PathBuf;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::UnixStream;
use uuid::Uuid;

#[derive(Debug, Parser)]
#[command(name = "alloyctl", about = "control plane for silicon-alloy bottles")]
struct Cli {
    #[arg(long, value_name = "PATH")]
    socket: Option<PathBuf>,

    #[command(subcommand)]
    command: Command,
}

#[derive(Debug, Subcommand)]
enum Command {
    /// create a fresh bottle
    Create {
        #[arg(value_name = "NAME")]
        name: String,
    },
    /// list known bottles
    List,
    /// run an executable inside a bottle
    Run {
        #[arg(value_name = "NAME")]
        name: String,
        #[arg(value_name = "EXECUTABLE")]
        executable: String,
        #[arg(value_name = "ARGS", trailing_var_arg = true)]
        args: Vec<String>,
    },
    /// remove a bottle and its data
    Destroy {
        #[arg(value_name = "NAME")]
        name: String,
    },
    /// list community recipes
    Recipes,
    /// apply a recipe to a bottle
    Apply {
        #[arg(value_name = "BOTTLE")]
        bottle: String,
        #[arg(value_name = "RECIPE_ID")]
        recipe: String,
    },
    /// make sure the daemon is up
    Ping,
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();
    let socket = cli
        .socket
        .or_else(|| std::env::var("SILICON_ALLOY_SOCKET").map(PathBuf::from).ok())
        .unwrap_or_else(default_socket_path);

    let request = DaemonRequest {
        id: Uuid::new_v4(),
        command: match cli.command {
            Command::Create { name } => DaemonCommand::Create { name },
            Command::List => DaemonCommand::List,
            Command::Run {
                name,
                executable,
                args,
            } => DaemonCommand::Run {
                name,
                executable,
                args,
                env: None,
            },
            Command::Destroy { name } => DaemonCommand::Destroy { name },
            Command::Recipes => DaemonCommand::ListRecipes,
            Command::Apply { bottle, recipe } => DaemonCommand::ApplyRecipe { bottle, recipe },
            Command::Ping => DaemonCommand::Ping,
        },
    };

    let response = send_request(&socket, request).await?;
    match response.status {
        DaemonStatus::Ok => {
            if let Some(result) = response.result {
                println!("{}", serde_json::to_string_pretty(&result)?);
            } else {
                println!("ok");
            }
        }
        DaemonStatus::Error { message } => {
            anyhow::bail!(message);
        }
    }

    Ok(())
}

fn default_socket_path() -> PathBuf {
    let base = dirs::runtime_dir()
        .or_else(|| dirs::data_dir())
        .unwrap_or_else(|| PathBuf::from("/tmp"));
    base.join("silicon-alloy").join("daemon.sock")
}

async fn send_request(socket: &PathBuf, request: DaemonRequest) -> Result<DaemonResponse> {
    let mut stream = UnixStream::connect(socket)
        .await
        .with_context(|| format!("cannot reach daemon at {}", socket.display()))?;

    let payload = serde_json::to_vec(&request)?;
    stream.write_all(&payload).await?;
    stream.write_all(b"\n").await?;

    let mut reader = BufReader::new(stream);
    let mut line = String::new();
    reader.read_line(&mut line).await?;
    let response: DaemonResponse = serde_json::from_str(&line)?;
    Ok(response)
}

