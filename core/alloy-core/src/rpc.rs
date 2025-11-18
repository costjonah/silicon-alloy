use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "command", rename_all = "snake_case")]
pub enum DaemonCommand {
    Create { name: String },
    List,
    Run {
        name: String,
        executable: String,
        args: Vec<String>,
        env: Option<HashMap<String, String>>,
    },
    Destroy { name: String },
    Ping,
    ListRecipes,
    ApplyRecipe {
        bottle: String,
        recipe: String,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DaemonRequest {
    pub id: Uuid,
    pub command: DaemonCommand,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DaemonResponse {
    pub id: Uuid,
    pub status: DaemonStatus,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub result: Option<serde_json::Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "state", rename_all = "snake_case")]
pub enum DaemonStatus {
    Ok,
    Error { message: String },
}

impl DaemonResponse {
    pub fn ok(id: Uuid, result: serde_json::Value) -> Self {
        Self {
            id,
            status: DaemonStatus::Ok,
            result: Some(result),
        }
    }

    pub fn empty(id: Uuid) -> Self {
        Self {
            id,
            status: DaemonStatus::Ok,
            result: None,
        }
    }

    pub fn error(id: Uuid, message: impl Into<String>) -> Self {
        Self {
            id,
            status: DaemonStatus::Error {
                message: message.into(),
            },
            result: None,
        }
    }
}

