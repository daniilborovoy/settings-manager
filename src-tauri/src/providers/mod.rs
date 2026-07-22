//! Providers fetch and persist key/value variables in external services.
//!
//! Each provider reads its connection settings from an untyped JSON `config`
//! blob stored per source in SQLite; [`cfg_str`] extracts required fields.

use aws_config::{BehaviorVersion, Region, SdkConfig};
use aws_credential_types::Credentials;
use serde::{Deserialize, Deserializer, Serialize};

pub mod gitlab;
pub mod lambda;
pub mod secrets_manager;

/// Errors produced while talking to an external variable store.
#[derive(Debug, thiserror::Error)]
pub enum ProviderError {
    #[error("Unknown source type: {0}")]
    UnknownSourceType(String),
    #[error("Missing config field: {0}")]
    MissingConfigField(&'static str),
    #[error("GitLab {status}: {message}")]
    Gitlab {
        status: reqwest::StatusCode,
        message: String,
    },
    #[error("GitLab request failed: {0}")]
    Http(#[from] reqwest::Error),
    #[error("AWS Lambda: {0}")]
    Lambda(String),
    #[error("AWS Secrets Manager: {0}")]
    SecretsManager(String),
    #[error("Secret value is not a JSON object of key/value pairs")]
    SecretNotJsonObject,
}

/// A single key/value variable. GitLab-specific metadata fields stay `None`
/// for plain key/value providers (Lambda, Secrets Manager).
#[derive(Debug, Serialize, Deserialize, Clone, Default)]
pub struct Variable {
    pub key: String,
    #[serde(default, deserialize_with = "null_as_empty_string")]
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

impl Variable {
    /// Plain key/value variable with no provider-specific metadata.
    pub fn kv(key: String, value: String) -> Self {
        Self {
            key,
            value,
            ..Self::default()
        }
    }
}

// GitLab omits or nulls `value` for hidden variables; treat both as empty.
fn null_as_empty_string<'de, D: Deserializer<'de>>(deserializer: D) -> Result<String, D::Error> {
    Ok(Option::<String>::deserialize(deserializer)?.unwrap_or_default())
}

/// Fetches all variables from the source identified by `source_type`.
pub async fn get_variables(
    source_type: &str,
    config: &serde_json::Value,
) -> Result<Vec<Variable>, ProviderError> {
    match source_type {
        "lambda" => lambda::get_variables(config).await,
        "gitlab_cicd" => gitlab::get_variables(config).await,
        "secrets_manager" => secrets_manager::get_variables(config).await,
        other => Err(ProviderError::UnknownSourceType(other.to_string())),
    }
}

/// Replaces the source's variables with `variables`.
pub async fn save_variables(
    source_type: &str,
    config: &serde_json::Value,
    variables: &[Variable],
) -> Result<(), ProviderError> {
    match source_type {
        "lambda" => lambda::save_variables(config, variables).await,
        "gitlab_cicd" => gitlab::save_variables(config, variables).await,
        "secrets_manager" => secrets_manager::save_variables(config, variables).await,
        other => Err(ProviderError::UnknownSourceType(other.to_string())),
    }
}

/// Builds an AWS SDK config from the static credentials stored in `config`.
pub async fn aws_sdk_config(config: &serde_json::Value) -> Result<SdkConfig, ProviderError> {
    let access_key = cfg_str(config, "aws_access_key_id")?;
    let secret_key = cfg_str(config, "aws_secret_access_key")?;
    let region = cfg_str(config, "aws_region")?;

    let creds = Credentials::new(access_key, secret_key, None, None, "settings-manager");
    Ok(aws_config::defaults(BehaviorVersion::latest())
        .region(Region::new(region.to_string()))
        .credentials_provider(creds)
        .load()
        .await)
}

/// Extracts a required string field from a source config.
///
/// # Errors
/// Returns [`ProviderError::MissingConfigField`] when the field is absent or
/// not a string.
pub fn cfg_str<'a>(
    config: &'a serde_json::Value,
    key: &'static str,
) -> Result<&'a str, ProviderError> {
    config
        .get(key)
        .and_then(|v| v.as_str())
        .ok_or(ProviderError::MissingConfigField(key))
}
