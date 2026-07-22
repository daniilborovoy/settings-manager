//! Tauri IPC commands exposed to the frontend.

use std::sync::{Mutex, MutexGuard};

use rusqlite::Connection;
use tauri::State;

use crate::db::{self, Project, ProjectWithSources, Source, SourceSummary};
use crate::error::AppError;
use crate::providers::{self, Variable};

pub struct AppState {
    pub db: Mutex<Connection>,
}

impl AppState {
    fn conn(&self) -> Result<MutexGuard<'_, Connection>, AppError> {
        self.db.lock().map_err(|_| AppError::LockPoisoned)
    }

    // Locks, loads, and releases before any await: the guard must not be held
    // across await points in the async commands below.
    fn load_source(&self, id: i64) -> Result<Source, AppError> {
        let conn = self.conn()?;
        db::get_source(&conn, id)?.ok_or(AppError::NotFound("Source"))
    }
}

/* ── Projects ── */

#[tauri::command]
pub fn list_projects_with_sources(
    state: State<'_, AppState>,
) -> Result<Vec<ProjectWithSources>, AppError> {
    let conn = state.conn()?;
    Ok(db::list_projects_with_sources(&conn)?)
}

#[tauri::command]
pub fn create_project(state: State<'_, AppState>, name: String) -> Result<Project, AppError> {
    let conn = state.conn()?;
    Ok(db::create_project(&conn, &name)?)
}

#[tauri::command]
pub fn rename_project(
    state: State<'_, AppState>,
    id: i64,
    name: String,
) -> Result<Project, AppError> {
    let conn = state.conn()?;
    db::rename_project(&conn, id, &name)?.ok_or(AppError::NotFound("Project"))
}

#[tauri::command]
pub fn delete_project(state: State<'_, AppState>, id: i64) -> Result<(), AppError> {
    let conn = state.conn()?;
    if !db::delete_project(&conn, id)? {
        return Err(AppError::NotFound("Project"));
    }
    Ok(())
}

#[tauri::command]
pub fn reorder_projects(state: State<'_, AppState>, ordered_ids: Vec<i64>) -> Result<(), AppError> {
    let mut conn = state.conn()?;
    Ok(db::reorder_projects(&mut conn, &ordered_ids)?)
}

/* ── Sources ── */

#[tauri::command]
pub fn create_source(
    state: State<'_, AppState>,
    project_id: i64,
    name: String,
    r#type: String,
    config: serde_json::Value,
) -> Result<SourceSummary, AppError> {
    let conn = state.conn()?;
    let source = db::create_source(&conn, project_id, &name, &r#type, &config)?;
    Ok(SourceSummary::from(&source))
}

#[tauri::command]
pub fn rename_source(
    state: State<'_, AppState>,
    id: i64,
    name: String,
) -> Result<SourceSummary, AppError> {
    let conn = state.conn()?;
    let source = db::rename_source(&conn, id, &name)?.ok_or(AppError::NotFound("Source"))?;
    Ok(SourceSummary::from(&source))
}

#[tauri::command]
pub fn update_gitlab_token(
    state: State<'_, AppState>,
    id: i64,
    token: String,
) -> Result<(), AppError> {
    let conn = state.conn()?;
    let mut source = db::get_source(&conn, id)?.ok_or(AppError::NotFound("Source"))?;
    if source.type_ != "gitlab_cicd" {
        return Err(AppError::NotGitlabSource);
    }
    let obj = source
        .config
        .as_object_mut()
        .ok_or(AppError::MalformedConfig)?;
    obj.insert("private_token".into(), serde_json::Value::String(token));
    db::update_source_config(&conn, id, &source.config)?.ok_or(AppError::NotFound("Source"))?;
    Ok(())
}

#[tauri::command]
pub fn delete_source(state: State<'_, AppState>, id: i64) -> Result<(), AppError> {
    let conn = state.conn()?;
    if !db::delete_source(&conn, id)? {
        return Err(AppError::NotFound("Source"));
    }
    Ok(())
}

#[tauri::command]
pub fn reorder_sources(
    state: State<'_, AppState>,
    project_id: i64,
    ordered_ids: Vec<i64>,
) -> Result<(), AppError> {
    let mut conn = state.conn()?;
    Ok(db::reorder_sources(&mut conn, project_id, &ordered_ids)?)
}

/* ── Variables ── */

#[tauri::command]
pub async fn get_variables(
    state: State<'_, AppState>,
    id: i64,
) -> Result<Vec<Variable>, AppError> {
    let source = state.load_source(id)?;
    Ok(providers::get_variables(&source.type_, &source.config).await?)
}

#[tauri::command]
pub async fn save_variables(
    state: State<'_, AppState>,
    id: i64,
    variables: Vec<Variable>,
) -> Result<(), AppError> {
    let source = state.load_source(id)?;
    Ok(providers::save_variables(&source.type_, &source.config, &variables).await?)
}
