use std::sync::Mutex;

use rusqlite::Connection;
use tauri::State;

use crate::db::{self, Project, ProjectWithSources, Source, SourceSummary};
use crate::providers::{self, Variable};

pub struct AppState {
    pub db: Mutex<Connection>,
}

fn map_db_err(e: rusqlite::Error) -> String {
    format!("DB error: {e}")
}

fn load_source(state: &State<'_, AppState>, id: i64) -> Result<Source, String> {
    let conn = state.db.lock().map_err(|e| e.to_string())?;
    db::get_source(&conn, id)
        .map_err(map_db_err)?
        .ok_or_else(|| "Source not found".into())
}

/* ── Projects ── */

#[tauri::command]
pub fn list_projects_with_sources(
    state: State<'_, AppState>,
) -> Result<Vec<ProjectWithSources>, String> {
    let conn = state.db.lock().map_err(|e| e.to_string())?;
    db::list_projects_with_sources(&conn).map_err(map_db_err)
}

#[tauri::command]
pub fn create_project(state: State<'_, AppState>, name: String) -> Result<Project, String> {
    let conn = state.db.lock().map_err(|e| e.to_string())?;
    db::create_project(&conn, &name).map_err(map_db_err)
}

#[tauri::command]
pub fn rename_project(
    state: State<'_, AppState>,
    id: i64,
    name: String,
) -> Result<Project, String> {
    let conn = state.db.lock().map_err(|e| e.to_string())?;
    db::rename_project(&conn, id, &name)
        .map_err(map_db_err)?
        .ok_or_else(|| "Project not found".into())
}

#[tauri::command]
pub fn delete_project(state: State<'_, AppState>, id: i64) -> Result<(), String> {
    let conn = state.db.lock().map_err(|e| e.to_string())?;
    let ok = db::delete_project(&conn, id).map_err(map_db_err)?;
    if !ok {
        return Err("Project not found".into());
    }
    Ok(())
}

#[tauri::command]
pub fn reorder_projects(
    state: State<'_, AppState>,
    ordered_ids: Vec<i64>,
) -> Result<(), String> {
    let mut conn = state.db.lock().map_err(|e| e.to_string())?;
    db::reorder_projects(&mut conn, &ordered_ids).map_err(map_db_err)
}

/* ── Sources ── */

#[tauri::command]
pub fn create_source(
    state: State<'_, AppState>,
    project_id: i64,
    name: String,
    r#type: String,
    config: serde_json::Value,
) -> Result<SourceSummary, String> {
    let conn = state.db.lock().map_err(|e| e.to_string())?;
    let s = db::create_source(&conn, project_id, &name, &r#type, &config).map_err(map_db_err)?;
    Ok(SourceSummary::from(&s))
}

#[tauri::command]
pub fn rename_source(
    state: State<'_, AppState>,
    id: i64,
    name: String,
) -> Result<SourceSummary, String> {
    let conn = state.db.lock().map_err(|e| e.to_string())?;
    let s = db::rename_source(&conn, id, &name)
        .map_err(map_db_err)?
        .ok_or_else(|| "Source not found".to_string())?;
    Ok(SourceSummary::from(&s))
}

#[tauri::command]
pub fn delete_source(state: State<'_, AppState>, id: i64) -> Result<(), String> {
    let conn = state.db.lock().map_err(|e| e.to_string())?;
    let ok = db::delete_source(&conn, id).map_err(map_db_err)?;
    if !ok {
        return Err("Source not found".into());
    }
    Ok(())
}

#[tauri::command]
pub fn reorder_sources(
    state: State<'_, AppState>,
    project_id: i64,
    ordered_ids: Vec<i64>,
) -> Result<(), String> {
    let mut conn = state.db.lock().map_err(|e| e.to_string())?;
    db::reorder_sources(&mut conn, project_id, &ordered_ids).map_err(map_db_err)
}

#[tauri::command]
pub async fn get_variables(
    state: State<'_, AppState>,
    id: i64,
) -> Result<Vec<Variable>, String> {
    let source = load_source(&state, id)?;
    providers::get_variables(&source.type_, &source.config).await
}

#[tauri::command]
pub async fn save_variables(
    state: State<'_, AppState>,
    id: i64,
    variables: Vec<Variable>,
) -> Result<(), String> {
    let source = load_source(&state, id)?;
    providers::save_variables(&source.type_, &source.config, &variables).await
}
