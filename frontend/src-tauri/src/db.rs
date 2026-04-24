use chrono::{DateTime, Utc};
use rusqlite::{params, Connection, Row};
use serde::{Deserialize, Serialize};
use std::path::Path;

#[derive(Debug, Serialize, Deserialize)]
pub struct Source {
    pub id: i64,
    pub project_id: i64,
    pub name: String,
    #[serde(rename = "type")]
    pub type_: String,
    #[serde(skip_serializing)]
    pub config: serde_json::Value,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Serialize, Clone)]
pub struct SourceSummary {
    pub id: i64,
    pub project_id: i64,
    pub name: String,
    #[serde(rename = "type")]
    pub type_: String,
    pub created_at: DateTime<Utc>,
}

impl From<&Source> for SourceSummary {
    fn from(s: &Source) -> Self {
        Self {
            id: s.id,
            project_id: s.project_id,
            name: s.name.clone(),
            type_: s.type_.clone(),
            created_at: s.created_at,
        }
    }
}

#[derive(Debug, Serialize)]
pub struct Project {
    pub id: i64,
    pub name: String,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Serialize)]
pub struct ProjectWithSources {
    pub id: i64,
    pub name: String,
    pub created_at: DateTime<Utc>,
    pub sources: Vec<SourceSummary>,
}

fn row_to_source(row: &Row<'_>) -> rusqlite::Result<Source> {
    let config_str: String = row.get("config")?;
    let config: serde_json::Value = serde_json::from_str(&config_str)
        .map_err(|e| rusqlite::Error::FromSqlConversionFailure(0, rusqlite::types::Type::Text, Box::new(e)))?;
    Ok(Source {
        id: row.get("id")?,
        project_id: row.get("project_id")?,
        name: row.get("name")?,
        type_: row.get("type")?,
        config,
        created_at: row.get("created_at")?,
    })
}

fn row_to_source_summary(row: &Row<'_>) -> rusqlite::Result<SourceSummary> {
    Ok(SourceSummary {
        id: row.get("id")?,
        project_id: row.get("project_id")?,
        name: row.get("name")?,
        type_: row.get("type")?,
        created_at: row.get("created_at")?,
    })
}

fn row_to_project(row: &Row<'_>) -> rusqlite::Result<Project> {
    Ok(Project {
        id: row.get("id")?,
        name: row.get("name")?,
        created_at: row.get("created_at")?,
    })
}

pub fn open(path: &Path) -> rusqlite::Result<Connection> {
    let conn = Connection::open(path)?;
    conn.execute("PRAGMA foreign_keys = ON", [])?;

    conn.execute(
        "CREATE TABLE IF NOT EXISTS projects (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            created_at TEXT NOT NULL
        )",
        [],
    )?;

    conn.execute(
        "CREATE TABLE IF NOT EXISTS sources (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            type TEXT NOT NULL,
            config TEXT NOT NULL,
            created_at TEXT NOT NULL,
            project_id INTEGER REFERENCES projects(id) ON DELETE CASCADE
        )",
        [],
    )?;

    migrate_add_project_id(&conn)?;
    backfill_default_project(&conn)?;

    Ok(conn)
}

fn migrate_add_project_id(conn: &Connection) -> rusqlite::Result<()> {
    let mut stmt = conn.prepare("PRAGMA table_info(sources)")?;
    let has_column = stmt
        .query_map([], |row| row.get::<_, String>(1))?
        .filter_map(|r| r.ok())
        .any(|col| col == "project_id");
    drop(stmt);
    if !has_column {
        conn.execute(
            "ALTER TABLE sources ADD COLUMN project_id INTEGER REFERENCES projects(id) ON DELETE CASCADE",
            [],
        )?;
    }
    Ok(())
}

fn backfill_default_project(conn: &Connection) -> rusqlite::Result<()> {
    let orphan_count: i64 = conn.query_row(
        "SELECT COUNT(*) FROM sources WHERE project_id IS NULL",
        [],
        |r| r.get(0),
    )?;
    if orphan_count == 0 {
        return Ok(());
    }
    let now = Utc::now();
    conn.execute(
        "INSERT INTO projects (name, created_at) VALUES (?1, ?2)",
        params!["Default", now],
    )?;
    let default_id = conn.last_insert_rowid();
    conn.execute(
        "UPDATE sources SET project_id = ?1 WHERE project_id IS NULL",
        params![default_id],
    )?;
    Ok(())
}

/* ── Projects ── */

pub fn list_projects(conn: &Connection) -> rusqlite::Result<Vec<Project>> {
    let mut stmt = conn.prepare("SELECT id, name, created_at FROM projects ORDER BY id")?;
    let rows = stmt.query_map([], row_to_project)?;
    rows.collect()
}

pub fn list_projects_with_sources(conn: &Connection) -> rusqlite::Result<Vec<ProjectWithSources>> {
    let projects = list_projects(conn)?;
    let mut stmt = conn.prepare(
        "SELECT id, project_id, name, type, created_at FROM sources ORDER BY id",
    )?;
    let all_sources: Vec<SourceSummary> = stmt
        .query_map([], row_to_source_summary)?
        .collect::<Result<_, _>>()?;

    Ok(projects
        .into_iter()
        .map(|p| {
            let sources = all_sources
                .iter()
                .filter(|s| s.project_id == p.id)
                .cloned()
                .collect();
            ProjectWithSources {
                id: p.id,
                name: p.name,
                created_at: p.created_at,
                sources,
            }
        })
        .collect())
}

pub fn create_project(conn: &Connection, name: &str) -> rusqlite::Result<Project> {
    let now = Utc::now();
    conn.execute(
        "INSERT INTO projects (name, created_at) VALUES (?1, ?2)",
        params![name, now],
    )?;
    let id = conn.last_insert_rowid();
    Ok(Project {
        id,
        name: name.to_string(),
        created_at: now,
    })
}

pub fn rename_project(conn: &Connection, id: i64, name: &str) -> rusqlite::Result<Option<Project>> {
    let updated = conn.execute(
        "UPDATE projects SET name = ?1 WHERE id = ?2",
        params![name, id],
    )?;
    if updated == 0 {
        return Ok(None);
    }
    let mut stmt = conn.prepare("SELECT id, name, created_at FROM projects WHERE id = ?1")?;
    let mut rows = stmt.query_map(params![id], row_to_project)?;
    match rows.next() {
        Some(r) => r.map(Some),
        None => Ok(None),
    }
}

pub fn delete_project(conn: &Connection, id: i64) -> rusqlite::Result<bool> {
    let deleted = conn.execute("DELETE FROM projects WHERE id = ?1", params![id])?;
    Ok(deleted > 0)
}

/* ── Sources ── */

pub fn get_source(conn: &Connection, id: i64) -> rusqlite::Result<Option<Source>> {
    let mut stmt = conn.prepare(
        "SELECT id, project_id, name, type, config, created_at FROM sources WHERE id = ?1",
    )?;
    let mut rows = stmt.query_map(params![id], row_to_source)?;
    match rows.next() {
        Some(r) => r.map(Some),
        None => Ok(None),
    }
}

pub fn create_source(
    conn: &Connection,
    project_id: i64,
    name: &str,
    type_: &str,
    config: &serde_json::Value,
) -> rusqlite::Result<Source> {
    let now = Utc::now();
    let config_str = serde_json::to_string(config).expect("config serialize");
    conn.execute(
        "INSERT INTO sources (project_id, name, type, config, created_at) VALUES (?1, ?2, ?3, ?4, ?5)",
        params![project_id, name, type_, config_str, now],
    )?;
    let id = conn.last_insert_rowid();
    Ok(Source {
        id,
        project_id,
        name: name.to_string(),
        type_: type_.to_string(),
        config: config.clone(),
        created_at: now,
    })
}

pub fn rename_source(conn: &Connection, id: i64, name: &str) -> rusqlite::Result<Option<Source>> {
    let updated = conn.execute(
        "UPDATE sources SET name = ?1 WHERE id = ?2",
        params![name, id],
    )?;
    if updated == 0 {
        return Ok(None);
    }
    get_source(conn, id)
}

pub fn delete_source(conn: &Connection, id: i64) -> rusqlite::Result<bool> {
    let deleted = conn.execute("DELETE FROM sources WHERE id = ?1", params![id])?;
    Ok(deleted > 0)
}
