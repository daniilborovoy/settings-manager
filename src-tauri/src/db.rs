//! SQLite persistence for projects and sources, including schema migrations.
//!
//! All functions return [`rusqlite::Result`]; the command layer wraps them
//! into the app-level error type.

use std::collections::HashMap;
use std::path::Path;

use chrono::{DateTime, Utc};
use rusqlite::{params, Connection, OptionalExtension, Row};
use serde::{Deserialize, Serialize};

/// A configured variable source. `config` holds provider-specific settings
/// (credentials included) and is never serialized to the frontend.
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

/// Frontend-facing view of a [`Source`] without its config.
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
    let config: serde_json::Value = serde_json::from_str(&config_str).map_err(|e| {
        rusqlite::Error::FromSqlConversionFailure(0, rusqlite::types::Type::Text, Box::new(e))
    })?;
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

fn config_to_sql(config: &serde_json::Value) -> rusqlite::Result<String> {
    serde_json::to_string(config).map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))
}

/// Opens (or creates) the database at `path` and applies migrations.
pub fn open(path: &Path) -> rusqlite::Result<Connection> {
    let conn = Connection::open(path)?;
    init(&conn)?;
    Ok(conn)
}

fn init(conn: &Connection) -> rusqlite::Result<()> {
    conn.pragma_update(None, "foreign_keys", "ON")?;

    conn.execute(
        "CREATE TABLE IF NOT EXISTS projects (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            sort_order INTEGER NOT NULL DEFAULT 0,
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
            sort_order INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            project_id INTEGER REFERENCES projects(id) ON DELETE CASCADE
        )",
        [],
    )?;

    migrate_add_project_id(conn)?;
    migrate_add_sort_order(conn)?;
    backfill_default_project(conn)?;
    backfill_project_sort_order(conn)?;
    backfill_source_sort_order(conn)?;

    Ok(())
}

/* ── Migrations ── */

fn column_exists(conn: &Connection, table: &str, column: &str) -> rusqlite::Result<bool> {
    // PRAGMA arguments cannot be bound as parameters; `table` is an internal
    // constant, never user input.
    let mut stmt = conn.prepare(&format!("PRAGMA table_info({table})"))?;
    let exists = stmt
        .query_map([], |row| row.get::<_, String>(1))?
        .filter_map(Result::ok)
        .any(|col| col == column);
    Ok(exists)
}

fn migrate_add_project_id(conn: &Connection) -> rusqlite::Result<()> {
    if !column_exists(conn, "sources", "project_id")? {
        conn.execute(
            "ALTER TABLE sources ADD COLUMN project_id INTEGER REFERENCES projects(id) ON DELETE CASCADE",
            [],
        )?;
    }
    Ok(())
}

fn migrate_add_sort_order(conn: &Connection) -> rusqlite::Result<()> {
    if !column_exists(conn, "projects", "sort_order")? {
        conn.execute(
            "ALTER TABLE projects ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0",
            [],
        )?;
    }
    if !column_exists(conn, "sources", "sort_order")? {
        conn.execute(
            "ALTER TABLE sources ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0",
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
    conn.execute(
        "INSERT INTO projects (name, created_at) VALUES (?1, ?2)",
        params!["Default", Utc::now()],
    )?;
    let default_id = conn.last_insert_rowid();
    conn.execute(
        "UPDATE sources SET project_id = ?1 WHERE project_id IS NULL",
        params![default_id],
    )?;
    Ok(())
}

fn backfill_project_sort_order(conn: &Connection) -> rusqlite::Result<()> {
    let mut stmt = conn.prepare("SELECT id FROM projects ORDER BY sort_order, id")?;
    let ids: Vec<i64> = stmt
        .query_map([], |row| row.get(0))?
        .collect::<Result<_, _>>()?;
    drop(stmt);

    for (index, id) in ids.into_iter().enumerate() {
        conn.execute(
            "UPDATE projects SET sort_order = ?1 WHERE id = ?2",
            params![index as i64, id],
        )?;
    }
    Ok(())
}

fn backfill_source_sort_order(conn: &Connection) -> rusqlite::Result<()> {
    let mut stmt =
        conn.prepare("SELECT id, project_id FROM sources ORDER BY project_id, sort_order, id")?;
    let rows: Vec<(i64, i64)> = stmt
        .query_map([], |row| Ok((row.get(0)?, row.get(1)?)))?
        .collect::<Result<_, _>>()?;
    drop(stmt);

    let mut current_project_id = None;
    let mut order = 0_i64;
    for (id, project_id) in rows {
        if current_project_id != Some(project_id) {
            current_project_id = Some(project_id);
            order = 0;
        }
        conn.execute(
            "UPDATE sources SET sort_order = ?1 WHERE id = ?2",
            params![order, id],
        )?;
        order += 1;
    }
    Ok(())
}

/* ── Projects ── */

pub fn list_projects(conn: &Connection) -> rusqlite::Result<Vec<Project>> {
    let mut stmt =
        conn.prepare("SELECT id, name, created_at FROM projects ORDER BY sort_order, id")?;
    let rows = stmt.query_map([], row_to_project)?;
    rows.collect()
}

pub fn list_projects_with_sources(conn: &Connection) -> rusqlite::Result<Vec<ProjectWithSources>> {
    let projects = list_projects(conn)?;
    let mut stmt = conn.prepare(
        "SELECT id, project_id, name, type, created_at FROM sources ORDER BY project_id, sort_order, id",
    )?;
    let mut by_project: HashMap<i64, Vec<SourceSummary>> = HashMap::new();
    for source in stmt.query_map([], row_to_source_summary)? {
        let source = source?;
        by_project.entry(source.project_id).or_default().push(source);
    }

    Ok(projects
        .into_iter()
        .map(|p| ProjectWithSources {
            sources: by_project.remove(&p.id).unwrap_or_default(),
            id: p.id,
            name: p.name,
            created_at: p.created_at,
        })
        .collect())
}

pub fn create_project(conn: &Connection, name: &str) -> rusqlite::Result<Project> {
    let now = Utc::now();
    let sort_order: i64 = conn.query_row(
        "SELECT COALESCE(MAX(sort_order), -1) + 1 FROM projects",
        [],
        |row| row.get(0),
    )?;
    conn.execute(
        "INSERT INTO projects (name, sort_order, created_at) VALUES (?1, ?2, ?3)",
        params![name, sort_order, now],
    )?;
    Ok(Project {
        id: conn.last_insert_rowid(),
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
    conn.query_row(
        "SELECT id, name, created_at FROM projects WHERE id = ?1",
        params![id],
        row_to_project,
    )
    .optional()
}

pub fn delete_project(conn: &Connection, id: i64) -> rusqlite::Result<bool> {
    let deleted = conn.execute("DELETE FROM projects WHERE id = ?1", params![id])?;
    Ok(deleted > 0)
}

/// Rewrites `sort_order` to match `ordered_ids`, which must list every
/// project exactly once.
pub fn reorder_projects(conn: &mut Connection, ordered_ids: &[i64]) -> rusqlite::Result<()> {
    let total: i64 = conn.query_row("SELECT COUNT(*) FROM projects", [], |row| row.get(0))?;
    if total != ordered_ids.len() as i64 {
        return Err(rusqlite::Error::InvalidParameterName(
            "ordered_ids must contain every project exactly once".into(),
        ));
    }

    let tx = conn.transaction()?;
    for (index, id) in ordered_ids.iter().enumerate() {
        let updated = tx.execute(
            "UPDATE projects SET sort_order = ?1 WHERE id = ?2",
            params![index as i64, id],
        )?;
        if updated == 0 {
            return Err(rusqlite::Error::QueryReturnedNoRows);
        }
    }
    tx.commit()
}

/* ── Sources ── */

pub fn get_source(conn: &Connection, id: i64) -> rusqlite::Result<Option<Source>> {
    conn.query_row(
        "SELECT id, project_id, name, type, config, created_at FROM sources WHERE id = ?1",
        params![id],
        row_to_source,
    )
    .optional()
}

pub fn create_source(
    conn: &Connection,
    project_id: i64,
    name: &str,
    type_: &str,
    config: &serde_json::Value,
) -> rusqlite::Result<Source> {
    let now = Utc::now();
    let sort_order: i64 = conn.query_row(
        "SELECT COALESCE(MAX(sort_order), -1) + 1 FROM sources WHERE project_id = ?1",
        params![project_id],
        |row| row.get(0),
    )?;
    conn.execute(
        "INSERT INTO sources (project_id, name, type, config, sort_order, created_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
        params![project_id, name, type_, config_to_sql(config)?, sort_order, now],
    )?;
    Ok(Source {
        id: conn.last_insert_rowid(),
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

pub fn update_source_config(
    conn: &Connection,
    id: i64,
    config: &serde_json::Value,
) -> rusqlite::Result<Option<Source>> {
    let updated = conn.execute(
        "UPDATE sources SET config = ?1 WHERE id = ?2",
        params![config_to_sql(config)?, id],
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

/// Rewrites `sort_order` within a project to match `ordered_ids`, which must
/// list every source in the project exactly once.
pub fn reorder_sources(
    conn: &mut Connection,
    project_id: i64,
    ordered_ids: &[i64],
) -> rusqlite::Result<()> {
    let total: i64 = conn.query_row(
        "SELECT COUNT(*) FROM sources WHERE project_id = ?1",
        params![project_id],
        |row| row.get(0),
    )?;
    if total != ordered_ids.len() as i64 {
        return Err(rusqlite::Error::InvalidParameterName(
            "ordered_ids must contain every source in the project exactly once".into(),
        ));
    }

    let tx = conn.transaction()?;
    for (index, id) in ordered_ids.iter().enumerate() {
        let updated = tx.execute(
            "UPDATE sources SET sort_order = ?1 WHERE id = ?2 AND project_id = ?3",
            params![index as i64, id, project_id],
        )?;
        if updated == 0 {
            return Err(rusqlite::Error::QueryReturnedNoRows);
        }
    }
    tx.commit()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_conn() -> Connection {
        let conn = Connection::open_in_memory().expect("in-memory db");
        init(&conn).expect("init schema");
        conn
    }

    mod create_source {
        use super::*;

        #[test]
        fn roundtrips_config_json() {
            let conn = test_conn();
            let project = create_project(&conn, "p").unwrap();
            let config = serde_json::json!({"secret_name": "my-app/prod"});

            let created = create_source(&conn, project.id, "s", "secrets_manager", &config).unwrap();
            let loaded = get_source(&conn, created.id).unwrap().unwrap();

            assert_eq!(loaded.config, config);
        }
    }

    mod get_source {
        use super::*;

        #[test]
        fn returns_none_when_missing() {
            let conn = test_conn();
            assert!(get_source(&conn, 42).unwrap().is_none());
        }
    }

    mod list_projects_with_sources {
        use super::*;

        #[test]
        fn groups_sources_under_their_project() {
            let conn = test_conn();
            let p1 = create_project(&conn, "one").unwrap();
            let p2 = create_project(&conn, "two").unwrap();
            let config = serde_json::json!({});
            create_source(&conn, p1.id, "a", "lambda", &config).unwrap();
            create_source(&conn, p2.id, "b", "lambda", &config).unwrap();
            create_source(&conn, p2.id, "c", "lambda", &config).unwrap();

            let listed = list_projects_with_sources(&conn).unwrap();

            let counts: Vec<usize> = listed.iter().map(|p| p.sources.len()).collect();
            assert_eq!(counts, [1, 2]);
        }
    }
}
