//! AWS Lambda environment variables provider.

use aws_sdk_lambda::{types::Environment, Client};
use aws_smithy_types::error::display::DisplayErrorContext;

use super::{aws_sdk_config, cfg_str, ProviderError, Variable};

async fn client(config: &serde_json::Value) -> Result<(Client, String), ProviderError> {
    let function_name = cfg_str(config, "function_name")?.to_string();
    let shared = aws_sdk_config(config).await?;
    Ok((Client::new(&shared), function_name))
}

fn lambda_error(e: impl std::error::Error) -> ProviderError {
    ProviderError::Lambda(DisplayErrorContext(&e).to_string())
}

pub async fn get_variables(config: &serde_json::Value) -> Result<Vec<Variable>, ProviderError> {
    let (client, function_name) = client(config).await?;
    let resp = client
        .get_function_configuration()
        .function_name(function_name)
        .send()
        .await
        .map_err(lambda_error)?;

    let map = resp
        .environment()
        .and_then(|e| e.variables())
        .cloned()
        .unwrap_or_default();

    let mut out: Vec<Variable> = map
        .into_iter()
        .map(|(key, value)| Variable::kv(key, value))
        .collect();
    out.sort_by(|a, b| a.key.cmp(&b.key));
    Ok(out)
}

pub async fn save_variables(
    config: &serde_json::Value,
    variables: &[Variable],
) -> Result<(), ProviderError> {
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
        .map_err(lambda_error)?;
    Ok(())
}
