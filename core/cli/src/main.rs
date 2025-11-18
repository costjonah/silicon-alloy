mod rpc_client;

use std::path::PathBuf;
use std::process::Stdio;

use anyhow::{anyhow, Context, Result};
use clap::{Parser, Subcommand};
use rpc_client::RpcClient;
use serde_json::json;
use tokio::process::Command;
use uuid::Uuid;

#[derive(Parser)]
#[command(author, version, about = "manage silicon alloy wine bottles")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// run the daemon in the foreground
    Daemon,

    /// show daemon status information
    Info,

    /// list bottles managed by the daemon
    List,

    /// create a new bottle
    Create {
        name: String,
        #[arg(long)]
        wine_version: String,
        #[arg(long)]
        wine_label: Option<String>,
        #[arg(long)]
        wine_path: Option<PathBuf>,
        #[arg(long)]
        channel: Option<String>,
    },

    /// delete a bottle by id
    Delete {
        id: Uuid,
    },

    /// run an executable inside a bottle
    Run {
        id: Uuid,
        executable: PathBuf,
        #[arg(trailing_var_arg = true)]
        args: Vec<String>,
    },

    /// recipe utilities
    Recipes {
        #[command(subcommand)]
        command: RecipeCommand,
    },

    /// runtime catalog helpers
    Runtime {
        #[command(subcommand)]
        command: RuntimeCommand,
    },
}

#[derive(Subcommand)]
enum RecipeCommand {
    /// list available recipes
    List,
    /// apply a recipe to a bottle
    Apply {
        #[arg(long)]
        bottle: Uuid,
        #[arg(long)]
        recipe: String,
    },
}

#[derive(Subcommand)]
enum RuntimeCommand {
    /// list known wine runtimes
    List,
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt::init();
    let cli = Cli::parse();
    match cli.command {
        Commands::Daemon => run_daemon().await,
        Commands::Info => {
            let response = RpcClient::call("service.info", json!({})).await?;
            println!("{}", serde_json::to_string_pretty(&response)?);
            Ok(())
        }
        Commands::List => {
            let response = RpcClient::call("bottle.list", json!({})).await?;
            println!("{}", serde_json::to_string_pretty(&response)?);
            Ok(())
        }
        Commands::Create {
            name,
            wine_version,
            wine_label,
            wine_path,
            channel,
        } => {
            let response = RpcClient::call(
                "bottle.create",
                json!({
                    "name": name,
                    "wine_version": wine_version,
                    "wine_label": wine_label,
                    "wine_path": wine_path,
                    "channel": channel,
                }),
            )
            .await?;
            println!("{}", serde_json::to_string_pretty(&response)?);
            Ok(())
        }
        Commands::Delete { id } => {
            let response = RpcClient::call("bottle.delete", json!({ "id": id })).await?;
            println!("{}", serde_json::to_string_pretty(&response)?);
            Ok(())
        }
        Commands::Run {
            id,
            executable,
            args,
        } => {
            let response = RpcClient::call(
                "bottle.run",
                json!({
                    "id": id,
                    "executable": executable,
                    "args": if args.is_empty() { None } else { Some(args) },
                }),
            )
            .await?;
            println!("{}", serde_json::to_string_pretty(&response)?);
            Ok(())
        }
        Commands::Recipes { command } => match command {
            RecipeCommand::List => {
                let response = RpcClient::call("recipe.list", json!({})).await?;
                println!("{}", serde_json::to_string_pretty(&response)?);
                Ok(())
            }
            RecipeCommand::Apply { bottle, recipe } => {
                let response = RpcClient::call(
                    "recipe.apply",
                    json!({
                        "bottle_id": bottle,
                        "recipe_id": recipe,
                    }),
                )
                .await?;
                println!("{}", serde_json::to_string_pretty(&response)?);
                Ok(())
            }
        },
        Commands::Runtime { command } => match command {
            RuntimeCommand::List => {
                let response = RpcClient::call("runtime.list", json!({})).await?;
                println!("{}", serde_json::to_string_pretty(&response)?);
                Ok(())
            }
        },
    }
}

async fn run_daemon() -> Result<()> {
    let mut cmd = Command::new("silicon-alloy-daemon");
    cmd.stdin(Stdio::null())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit());
    let status = cmd
        .spawn()
        .context("failed to spawn silicon-alloy-daemon")?
        .wait()
        .await?;
    if !status.success() {
        Err(anyhow!("daemon exited with {}", status))
    } else {
        Ok(())
    }
}

