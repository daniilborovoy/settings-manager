use aws_config::{BehaviorVersion, Region};
use aws_credential_types::Credentials;
use aws_sdk_lambda::{types::Environment, Client};

use super::{cfg_str, Variable};

async fn client(config: &serde_json::Value) -> Result<(Client, String), String> {
    let access_key = cfg_str(config, "aws_access_key_id")?;
    let secret_key = cfg_str(config, "aws_secret_access_key")?;
    let region = cfg_str(config, "aws_region")?;
    let function_name = cfg_str(config, "function_name")?.to_string();

    let creds = Credentials::new(access_key, secret_key, None, None, "settings-manager");
    let shared = aws_config::defaults(BehaviorVersion::latest())
        .region(Region::new(region.to_string()))
        .credentials_provider(creds)
        .load()
        .await;
    Ok((Client::new(&shared), function_name))
}

pub async fn get_variables(config: &serde_json::Value) -> Result<Vec<Variable>, String> {
    let (client, function_name) = client(config).await?;
    let resp = client
        .get_function_configuration()
        .function_name(function_name)
        .send()
        .await
        .map_err(|e| format!("AWS Lambda: {e}"))?;

    let map = resp
        .environment()
        .and_then(|e| e.variables())
        .cloned()
        .unwrap_or_default();

    let mut out: Vec<Variable> = map
        .into_iter()
        .map(|(k, v)| Variable {
            key: k,
            value: v,
            variable_type: None,
            environment_scope: None,
            protected: None,
            masked: None,
            hidden: None,
            raw: None,
            description: None,
        })
        .collect();
    out.sort_by(|a, b| a.key.cmp(&b.key));
    Ok(out)
}

pub async fn save_variables(
    config: &serde_json::Value,
    variables: &[Variable],
) -> Result<(), String> {
    let (client, function_name) = client(config).await?;
    let mut env_builder = Environment::builder();
    for v in variables {
        env_builder = env_builder.variables(&v.key, &v.value);
    }
    client
        .update_function_configuration()
        .function_name(function_name)
        .environment(env_builder.build())
        .send()
        .await
        .map_err(|e| format!("AWS Lambda: {e}"))?;
    Ok(())
}
