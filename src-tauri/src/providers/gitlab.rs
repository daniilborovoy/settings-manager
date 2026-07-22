//! GitLab CI/CD project variables provider.
//!
//! Saving diffs the desired state against the live one: removed variables are
//! deleted, the rest are created or updated. A variable's identity is the
//! `(key, environment_scope)` pair.

use std::collections::HashSet;

use reqwest::Response;
use serde_json::{json, Value};

use super::{cfg_str, ProviderError, Variable};

const PER_PAGE: usize = 100;

fn http_client() -> Result<reqwest::Client, ProviderError> {
    // Self-hosted GitLab instances frequently run on self-signed certificates.
    Ok(reqwest::Client::builder()
        .danger_accept_invalid_certs(true)
        .build()?)
}

fn base_url(config: &Value) -> Result<String, ProviderError> {
    let gitlab_url = cfg_str(config, "gitlab_url")?.trim_end_matches('/');
    let project_id = cfg_str(config, "project_id")?;
    let encoded = urlencoding::encode(project_id);
    Ok(format!("{gitlab_url}/api/v4/projects/{encoded}/variables"))
}

/// Pulls a human-readable message out of a GitLab error body, which may be
/// `{"message": "..."}`, `{"message": {field: [msgs]}}`, or `{"error": "..."}`.
fn extract_error(body: &str) -> String {
    let Ok(parsed) = serde_json::from_str::<Value>(body) else {
        return body.to_string();
    };
    if let Some(msg) = parsed.get("message") {
        if let Some(s) = msg.as_str() {
            return s.to_string();
        }
        if let Some(obj) = msg.as_object() {
            return obj
                .iter()
                .map(|(field, messages)| match messages {
                    Value::Array(arr) => format!(
                        "{field}: {}",
                        arr.iter()
                            .filter_map(Value::as_str)
                            .collect::<Vec<_>>()
                            .join(", ")
                    ),
                    other => format!("{field}: {other}"),
                })
                .collect::<Vec<_>>()
                .join("; ");
        }
        return msg.to_string();
    }
    if let Some(err) = parsed.get("error").and_then(Value::as_str) {
        return err.to_string();
    }
    body.to_string()
}

async fn error_from_response(resp: Response, context: Option<String>) -> ProviderError {
    let status = resp.status();
    let body = resp.text().await.unwrap_or_default();
    let mut message = extract_error(&body);
    if let Some(context) = context {
        message.push_str(&format!(" ({context})"));
    }
    ProviderError::Gitlab { status, message }
}

fn variable_to_body(v: &Variable) -> Value {
    let mut obj = serde_json::Map::new();
    obj.insert("key".into(), json!(v.key));
    obj.insert("value".into(), json!(v.value));
    if let Some(t) = &v.variable_type {
        obj.insert("variable_type".into(), json!(t));
    }
    if let Some(s) = &v.environment_scope {
        obj.insert("environment_scope".into(), json!(s));
    }
    if let Some(p) = v.protected {
        obj.insert("protected".into(), json!(p));
    }
    if let Some(m) = v.masked {
        obj.insert("masked".into(), json!(m));
    }
    if let Some(h) = v.hidden {
        // The API field for creating a hidden variable is `masked_and_hidden`,
        // while reads report it back as `hidden`.
        obj.insert("masked_and_hidden".into(), json!(h));
    }
    if let Some(r) = v.raw {
        obj.insert("raw".into(), json!(r));
    }
    if let Some(d) = &v.description {
        obj.insert("description".into(), json!(d));
    }
    Value::Object(obj)
}

fn identity(v: &Variable) -> (&str, &str) {
    (
        v.key.as_str(),
        v.environment_scope.as_deref().unwrap_or("*"),
    )
}

pub async fn get_variables(config: &Value) -> Result<Vec<Variable>, ProviderError> {
    let client = http_client()?;
    let url = base_url(config)?;
    let token = cfg_str(config, "private_token")?;

    let mut out = Vec::new();
    let mut page: u32 = 1;
    loop {
        let resp = client
            .get(&url)
            .header("PRIVATE-TOKEN", token)
            .query(&[("per_page", PER_PAGE.to_string()), ("page", page.to_string())])
            .send()
            .await?;

        if !resp.status().is_success() {
            return Err(error_from_response(resp, None).await);
        }

        let data: Vec<Variable> = resp.json().await?;
        let page_len = data.len();
        out.extend(data);
        if page_len < PER_PAGE {
            break;
        }
        page += 1;
    }
    Ok(out)
}

pub async fn save_variables(config: &Value, new_vars: &[Variable]) -> Result<(), ProviderError> {
    let client = http_client()?;
    let url = base_url(config)?;
    let token = cfg_str(config, "private_token")?;

    let existing = get_variables(config).await?;
    let existing_set: HashSet<(&str, &str)> = existing.iter().map(identity).collect();
    let new_set: HashSet<(&str, &str)> = new_vars.iter().map(identity).collect();

    for old in &existing {
        if new_set.contains(&identity(old)) {
            continue;
        }
        let (key, scope) = identity(old);
        let del_url = format!("{url}/{}", urlencoding::encode(key));
        let resp = client
            .delete(&del_url)
            .header("PRIVATE-TOKEN", token)
            .query(&[("filter[environment_scope]", scope)])
            .send()
            .await?;
        if !resp.status().is_success() {
            return Err(
                error_from_response(resp, Some(format!("while deleting {key}:{scope}"))).await,
            );
        }
    }

    for new_var in new_vars {
        let (key, scope) = identity(new_var);
        let body = variable_to_body(new_var);
        let (resp, action) = if existing_set.contains(&(key, scope)) {
            let put_url = format!("{url}/{}", urlencoding::encode(key));
            let resp = client
                .put(&put_url)
                .header("PRIVATE-TOKEN", token)
                .query(&[("filter[environment_scope]", scope)])
                .json(&body)
                .send()
                .await?;
            (resp, "updating")
        } else {
            let resp = client
                .post(&url)
                .header("PRIVATE-TOKEN", token)
                .json(&body)
                .send()
                .await?;
            (resp, "creating")
        };

        if !resp.status().is_success() {
            return Err(
                error_from_response(resp, Some(format!("while {action} {key}:{scope}"))).await,
            );
        }
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    mod extract_error {
        use super::*;

        #[test]
        fn returns_plain_string_message() {
            assert_eq!(
                extract_error(r#"{"message":"401 Unauthorized"}"#),
                "401 Unauthorized"
            );
        }

        #[test]
        fn joins_field_error_object() {
            assert_eq!(
                extract_error(r#"{"message":{"value":["is invalid","is too short"]}}"#),
                "value: is invalid, is too short"
            );
        }

        #[test]
        fn returns_error_field_when_no_message() {
            assert_eq!(extract_error(r#"{"error":"invalid_token"}"#), "invalid_token");
        }

        #[test]
        fn falls_back_to_raw_body_when_not_json() {
            assert_eq!(extract_error("<html>boom</html>"), "<html>boom</html>");
        }
    }

    mod identity {
        use super::*;

        #[test]
        fn defaults_missing_scope_to_wildcard() {
            let v = Variable::kv("KEY".into(), "v".into());
            assert_eq!(identity(&v), ("KEY", "*"));
        }
    }
}
