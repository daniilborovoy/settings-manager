//! AWS Secrets Manager provider.
//!
//! One secret holds all variables as a JSON object of key/value pairs — the
//! standard Secrets Manager key/value layout.

use aws_sdk_secretsmanager::Client;
use aws_smithy_types::error::display::DisplayErrorContext;
use serde_json::Value;

use super::{aws_sdk_config, cfg_str, ProviderError, Variable};

async fn client(config: &Value) -> Result<(Client, String), ProviderError> {
    let secret_name = cfg_str(config, "secret_name")?.to_string();
    let shared = aws_sdk_config(config).await?;
    Ok((Client::new(&shared), secret_name))
}

fn secrets_error(e: impl std::error::Error) -> ProviderError {
    ProviderError::SecretsManager(DisplayErrorContext(&e).to_string())
}

/// Parses a secret payload into sorted variables.
///
/// # Errors
/// Returns [`ProviderError::SecretNotJsonObject`] when the payload is not a
/// JSON object. Non-string values are kept as their JSON representation.
fn parse_secret_map(secret_string: &str) -> Result<Vec<Variable>, ProviderError> {
    let map: serde_json::Map<String, Value> =
        serde_json::from_str(secret_string).map_err(|_| ProviderError::SecretNotJsonObject)?;

    let mut out: Vec<Variable> = map
        .into_iter()
        .map(|(key, value)| {
            let value = match value {
                Value::String(s) => s,
                other => other.to_string(),
            };
            Variable::kv(key, value)
        })
        .collect();
    out.sort_by(|a, b| a.key.cmp(&b.key));
    Ok(out)
}

pub async fn get_variables(config: &Value) -> Result<Vec<Variable>, ProviderError> {
    let (client, secret_name) = client(config).await?;
    let resp = client
        .get_secret_value()
        .secret_id(secret_name)
        .send()
        .await
        .map_err(secrets_error)?;

    parse_secret_map(resp.secret_string().unwrap_or("{}"))
}

pub async fn save_variables(config: &Value, variables: &[Variable]) -> Result<(), ProviderError> {
    let (client, secret_name) = client(config).await?;
    let map: serde_json::Map<String, Value> = variables
        .iter()
        .map(|v| (v.key.clone(), Value::String(v.value.clone())))
        .collect();
    client
        .put_secret_value()
        .secret_id(secret_name)
        .secret_string(Value::Object(map).to_string())
        .send()
        .await
        .map_err(secrets_error)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    mod parse_secret_map {
        use super::*;

        #[test]
        fn parses_string_values_sorted_by_key() {
            let vars = parse_secret_map(r#"{"B":"2","A":"1"}"#).unwrap();
            let keys: Vec<&str> = vars.iter().map(|v| v.key.as_str()).collect();
            assert_eq!(keys, ["A", "B"]);
        }

        #[test]
        fn stringifies_non_string_values() {
            let vars = parse_secret_map(r#"{"PORT":8080}"#).unwrap();
            assert_eq!(vars[0].value, "8080");
        }

        #[test]
        fn rejects_non_object_payload() {
            let err = parse_secret_map("[1,2,3]").unwrap_err();
            assert!(matches!(err, ProviderError::SecretNotJsonObject));
        }
    }
}
