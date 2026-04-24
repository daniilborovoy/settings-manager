use serde::{Deserialize, Serialize};

pub mod gitlab;
pub mod lambda;

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Variable {
    pub key: String,
    pub value: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub variable_type: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub environment_scope: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub protected: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub masked: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub hidden: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub raw: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
}

pub async fn get_variables(
    source_type: &str,
    config: &serde_json::Value,
) -> Result<Vec<Variable>, String> {
    match source_type {
        "lambda" => lambda::get_variables(config).await,
        "gitlab_cicd" => gitlab::get_variables(config).await,
        other => Err(format!("Unknown source type: {other}")),
    }
}

pub async fn save_variables(
    source_type: &str,
    config: &serde_json::Value,
    variables: &[Variable],
) -> Result<(), String> {
    match source_type {
        "lambda" => lambda::save_variables(config, variables).await,
        "gitlab_cicd" => gitlab::save_variables(config, variables).await,
        other => Err(format!("Unknown source type: {other}")),
    }
}

pub fn cfg_str<'a>(config: &'a serde_json::Value, key: &str) -> Result<&'a str, String> {
    config
        .get(key)
        .and_then(|v| v.as_str())
        .ok_or_else(|| format!("Missing config field: {key}"))
}
