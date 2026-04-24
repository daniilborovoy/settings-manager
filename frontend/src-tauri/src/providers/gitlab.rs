use std::collections::HashSet;

use reqwest::StatusCode;
use serde_json::{json, Value};

use super::{cfg_str, Variable};

fn http_client() -> Result<reqwest::Client, String> {
    reqwest::Client::builder()
        .danger_accept_invalid_certs(true)
        .build()
        .map_err(|e| e.to_string())
}

fn base_url(config: &Value) -> Result<String, String> {
    let gitlab_url = cfg_str(config, "gitlab_url")?.trim_end_matches('/');
    let project_id = cfg_str(config, "project_id")?;
    let encoded = urlencoding::encode(project_id);
    Ok(format!("{gitlab_url}/api/v4/projects/{encoded}/variables"))
}

fn extract_error(status: StatusCode, body: &str) -> String {
    let parsed: Value = match serde_json::from_str(body) {
        Ok(v) => v,
        Err(_) => return format!("GitLab {status}: {body}"),
    };
    if let Some(msg) = parsed.get("message") {
        if let Some(s) = msg.as_str() {
            return format!("GitLab {status}: {s}");
        }
        // message may be an object mapping field → [messages]
        if let Some(obj) = msg.as_object() {
            let parts: Vec<String> = obj
                .iter()
                .map(|(k, v)| match v {
                    Value::Array(arr) => format!(
                        "{k}: {}",
                        arr.iter()
                            .filter_map(|x| x.as_str())
                            .collect::<Vec<_>>()
                            .join(", ")
                    ),
                    other => format!("{k}: {other}"),
                })
                .collect();
            return format!("GitLab {status}: {}", parts.join("; "));
        }
        return format!("GitLab {status}: {msg}");
    }
    if let Some(err) = parsed.get("error").and_then(|v| v.as_str()) {
        return format!("GitLab {status}: {err}");
    }
    format!("GitLab {status}: {body}")
}

fn parse_variable(v: &Value) -> Option<Variable> {
    let key = v.get("key")?.as_str()?.to_string();
    let value = v
        .get("value")
        .and_then(|x| x.as_str())
        .unwrap_or("")
        .to_string();
    Some(Variable {
        key,
        value,
        variable_type: v
            .get("variable_type")
            .and_then(|x| x.as_str())
            .map(String::from),
        environment_scope: v
            .get("environment_scope")
            .and_then(|x| x.as_str())
            .map(String::from),
        protected: v.get("protected").and_then(|x| x.as_bool()),
        masked: v.get("masked").and_then(|x| x.as_bool()),
        hidden: v.get("hidden").and_then(|x| x.as_bool()),
        raw: v.get("raw").and_then(|x| x.as_bool()),
        description: v
            .get("description")
            .and_then(|x| x.as_str())
            .map(String::from),
    })
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

type Identity = (String, String);

fn identity(v: &Variable) -> Identity {
    (
        v.key.clone(),
        v.environment_scope
            .clone()
            .unwrap_or_else(|| "*".to_string()),
    )
}

pub async fn get_variables(config: &Value) -> Result<Vec<Variable>, String> {
    let client = http_client()?;
    let url = base_url(config)?;
    let token = cfg_str(config, "private_token")?;

    let mut out = Vec::new();
    let mut page: u32 = 1;
    loop {
        let resp = client
            .get(&url)
            .header("PRIVATE-TOKEN", token)
            .query(&[("per_page", "100".to_string()), ("page", page.to_string())])
            .send()
            .await
            .map_err(|e| e.to_string())?;

        let status = resp.status();
        if !status.is_success() {
            let body = resp.text().await.unwrap_or_default();
            return Err(extract_error(status, &body));
        }

        let data: Vec<Value> = resp.json().await.map_err(|e| e.to_string())?;
        if data.is_empty() {
            break;
        }
        let len = data.len();
        for v in &data {
            if let Some(var) = parse_variable(v) {
                out.push(var);
            }
        }
        if len < 100 {
            break;
        }
        page += 1;
    }
    Ok(out)
}

pub async fn save_variables(config: &Value, new_vars: &[Variable]) -> Result<(), String> {
    let client = http_client()?;
    let url = base_url(config)?;
    let token = cfg_str(config, "private_token")?;

    let existing = get_variables(config).await?;
    let existing_set: HashSet<Identity> = existing.iter().map(identity).collect();
    let new_set: HashSet<Identity> = new_vars.iter().map(identity).collect();

    // Delete removed
    for old in &existing {
        let id = identity(old);
        if new_set.contains(&id) {
            continue;
        }
        let del_url = format!("{url}/{}", urlencoding::encode(&old.key));
        let scope = old
            .environment_scope
            .clone()
            .unwrap_or_else(|| "*".to_string());
        let resp = client
            .delete(&del_url)
            .header("PRIVATE-TOKEN", token)
            .query(&[("filter[environment_scope]", &scope)])
            .send()
            .await
            .map_err(|e| e.to_string())?;
        if !resp.status().is_success() {
            let status = resp.status();
            let body = resp.text().await.unwrap_or_default();
            return Err(format!(
                "{} {}",
                extract_error(status, &body),
                format!("(while deleting {}:{})", old.key, scope)
            ));
        }
    }

    // Create or update
    for new_var in new_vars {
        let id = identity(new_var);
        let body = variable_to_body(new_var);
        let (resp, action) = if existing_set.contains(&id) {
            let put_url = format!("{url}/{}", urlencoding::encode(&new_var.key));
            let scope = new_var
                .environment_scope
                .clone()
                .unwrap_or_else(|| "*".to_string());
            (
                client
                    .put(&put_url)
                    .header("PRIVATE-TOKEN", token)
                    .query(&[("filter[environment_scope]", &scope)])
                    .json(&body)
                    .send()
                    .await
                    .map_err(|e| e.to_string())?,
                "updating",
            )
        } else {
            (
                client
                    .post(&url)
                    .header("PRIVATE-TOKEN", token)
                    .json(&body)
                    .send()
                    .await
                    .map_err(|e| e.to_string())?,
                "creating",
            )
        };

        if !resp.status().is_success() {
            let status = resp.status();
            let error_body = resp.text().await.unwrap_or_default();
            return Err(format!(
                "{} (while {action} {}:{})",
                extract_error(status, &error_body),
                new_var.key,
                new_var.environment_scope.as_deref().unwrap_or("*")
            ));
        }
    }

    Ok(())
}
