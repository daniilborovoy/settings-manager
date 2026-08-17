import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// SQLite persistence for projects and sources. Same schema and migrations as
/// the Tauri backend, so it opens the database the Tauri app created at
/// ~/Library/Application Support/com.settings-manager.app/settings_manager.db.
final class Database {
    private let db: OpaquePointer

    init(path: String) throws {
        var handle: OpaquePointer?
        guard sqlite3_open(path, &handle) == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "cannot open"
            if let handle { sqlite3_close(handle) }
            throw AppError.db("\(message) (\(path))")
        }
        db = handle
        try exec("PRAGMA foreign_keys = ON")
        try migrate()
    }

    deinit { sqlite3_close(db) }

    // ── Low-level helpers ──

    private func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &err) == SQLITE_OK else {
            let message = err.map { String(cString: $0) } ?? "unknown SQLite error"
            sqlite3_free(err)
            throw AppError.db(message)
        }
    }

    private func prepare(_ sql: String, _ params: [Any?]) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw AppError.db(String(cString: sqlite3_errmsg(db)))
        }
        for (i, param) in params.enumerated() {
            let idx = Int32(i + 1)
            switch param {
            case let v as Int64: sqlite3_bind_int64(stmt, idx, v)
            case let v as Int: sqlite3_bind_int64(stmt, idx, Int64(v))
            case let v as String: sqlite3_bind_text(stmt, idx, v, -1, SQLITE_TRANSIENT)
            case nil: sqlite3_bind_null(stmt, idx)
            default:
                sqlite3_finalize(stmt)
                throw AppError.db("unsupported bind type")
            }
        }
        return stmt
    }

    @discardableResult
    private func run(_ sql: String, _ params: [Any?] = []) throws -> Int {
        let stmt = try prepare(sql, params)
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw AppError.db(String(cString: sqlite3_errmsg(db)))
        }
        return Int(sqlite3_changes(db))
    }

    private func rows<T>(_ sql: String, _ params: [Any?] = [], _ map: (OpaquePointer) -> T) throws -> [T] {
        let stmt = try prepare(sql, params)
        defer { sqlite3_finalize(stmt) }
        var out: [T] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(map(stmt))
        }
        return out
    }

    private func scalarInt(_ sql: String, _ params: [Any?] = []) throws -> Int64 {
        try rows(sql, params) { sqlite3_column_int64($0, 0) }.first ?? 0
    }

    private func text(_ stmt: OpaquePointer, _ col: Int32) -> String {
        sqlite3_column_text(stmt, col).map { String(cString: $0) } ?? ""
    }

    private func now() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: Date())
    }

    private func inTransaction(_ body: () throws -> Void) throws {
        try exec("BEGIN")
        do {
            try body()
            try exec("COMMIT")
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }

    // ── Schema & migrations (port of db.rs init) ──

    private func migrate() throws {
        try exec("""
            CREATE TABLE IF NOT EXISTS projects (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                sort_order INTEGER NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL
            )
            """)
        try exec("""
            CREATE TABLE IF NOT EXISTS sources (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                type TEXT NOT NULL,
                config TEXT NOT NULL,
                sort_order INTEGER NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL,
                project_id INTEGER REFERENCES projects(id) ON DELETE CASCADE
            )
            """)

        if try !columnExists("sources", "project_id") {
            try exec("ALTER TABLE sources ADD COLUMN project_id INTEGER REFERENCES projects(id) ON DELETE CASCADE")
        }
        if try !columnExists("projects", "sort_order") {
            try exec("ALTER TABLE projects ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0")
        }
        if try !columnExists("sources", "sort_order") {
            try exec("ALTER TABLE sources ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0")
        }
        // Swift-app-only table; the Tauri build ignores it.
        try exec("""
            CREATE TABLE IF NOT EXISTS credentials (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                kind TEXT NOT NULL,
                data TEXT NOT NULL,
                created_at TEXT NOT NULL
            )
            """)
        try backfillDefaultProject()
        try backfillSortOrders()
    }

    private func columnExists(_ table: String, _ column: String) throws -> Bool {
        // PRAGMA arguments cannot be bound; `table` is an internal constant.
        try rows("PRAGMA table_info(\(table))") { self.text($0, 1) }.contains(column)
    }

    private func backfillDefaultProject() throws {
        let orphans = try scalarInt("SELECT COUNT(*) FROM sources WHERE project_id IS NULL")
        guard orphans > 0 else { return }
        try run("INSERT INTO projects (name, created_at) VALUES (?, ?)", ["Default", now()])
        let defaultID = sqlite3_last_insert_rowid(db)
        try run("UPDATE sources SET project_id = ? WHERE project_id IS NULL", [defaultID])
    }

    private func backfillSortOrders() throws {
        let projectIDs = try rows("SELECT id FROM projects ORDER BY sort_order, id") { sqlite3_column_int64($0, 0) }
        for (index, id) in projectIDs.enumerated() {
            try run("UPDATE projects SET sort_order = ? WHERE id = ?", [Int64(index), id])
        }

        let sourceRows = try rows("SELECT id, project_id FROM sources ORDER BY project_id, sort_order, id") {
            (sqlite3_column_int64($0, 0), sqlite3_column_int64($0, 1))
        }
        var currentProject: Int64? = nil
        var order: Int64 = 0
        for (id, projectID) in sourceRows {
            if currentProject != projectID {
                currentProject = projectID
                order = 0
            }
            try run("UPDATE sources SET sort_order = ? WHERE id = ?", [order, id])
            order += 1
        }
    }

    // ── Projects ──

    func listProjectsWithSources() throws -> [Project] {
        let projects = try rows("SELECT id, name FROM projects ORDER BY sort_order, id") {
            (id: sqlite3_column_int64($0, 0), name: self.text($0, 1))
        }
        let sources = try rows(
            "SELECT id, project_id, name, type FROM sources ORDER BY project_id, sort_order, id"
        ) { stmt -> Source? in
            guard let type = SourceType(rawValue: self.text(stmt, 3)) else { return nil }
            return Source(
                id: sqlite3_column_int64(stmt, 0),
                projectID: sqlite3_column_int64(stmt, 1),
                name: self.text(stmt, 2),
                type: type
            )
        }.compactMap { $0 }

        let byProject = Dictionary(grouping: sources, by: \.projectID)
        return projects.map { Project(id: $0.id, name: $0.name, sources: byProject[$0.id] ?? []) }
    }

    func createProject(name: String) throws -> Int64 {
        let order = try scalarInt("SELECT COALESCE(MAX(sort_order), -1) + 1 FROM projects")
        try run("INSERT INTO projects (name, sort_order, created_at) VALUES (?, ?, ?)", [name, order, now()])
        return sqlite3_last_insert_rowid(db)
    }

    func renameProject(id: Int64, name: String) throws {
        guard try run("UPDATE projects SET name = ? WHERE id = ?", [name, id]) > 0 else {
            throw AppError.notFound("Project")
        }
    }

    func deleteProject(id: Int64) throws {
        guard try run("DELETE FROM projects WHERE id = ?", [id]) > 0 else {
            throw AppError.notFound("Project")
        }
    }

    func reorderProjects(orderedIDs: [Int64]) throws {
        let total = try scalarInt("SELECT COUNT(*) FROM projects")
        guard total == Int64(orderedIDs.count) else {
            throw AppError.db("ordered ids must contain every project exactly once")
        }
        try inTransaction {
            for (index, id) in orderedIDs.enumerated() {
                guard try run("UPDATE projects SET sort_order = ? WHERE id = ?", [Int64(index), id]) > 0 else {
                    throw AppError.notFound("Project")
                }
            }
        }
    }

    // ── Sources ──

    func sourceConfig(id: Int64) throws -> (type: SourceType, config: [String: String]) {
        let found = try rows("SELECT type, config FROM sources WHERE id = ?", [id]) {
            (type: self.text($0, 0), config: self.text($0, 1))
        }.first
        guard let found else { throw AppError.notFound("Source") }
        guard let type = SourceType(rawValue: found.type) else {
            throw AppError.db("Unknown source type: \(found.type)")
        }
        guard let data = found.config.data(using: .utf8),
              let config = try? JSONDecoder().decode([String: String].self, from: data) else {
            throw AppError.malformedConfig
        }
        return (type, config)
    }

    func createSource(projectID: Int64, name: String, type: SourceType, config: [String: String]) throws -> Int64 {
        let json = try JSONEncoder().encode(config)
        let order = try scalarInt(
            "SELECT COALESCE(MAX(sort_order), -1) + 1 FROM sources WHERE project_id = ?", [projectID]
        )
        try run(
            "INSERT INTO sources (project_id, name, type, config, sort_order, created_at) VALUES (?, ?, ?, ?, ?, ?)",
            [projectID, name, type.rawValue, String(decoding: json, as: UTF8.self), order, now()]
        )
        return sqlite3_last_insert_rowid(db)
    }

    func renameSource(id: Int64, name: String) throws {
        guard try run("UPDATE sources SET name = ? WHERE id = ?", [name, id]) > 0 else {
            throw AppError.notFound("Source")
        }
    }

    func updateGitlabToken(id: Int64, token: String) throws {
        let (type, config) = try sourceConfig(id: id)
        guard type == .gitlabCICD else { throw AppError.notGitlabSource }
        var updated = config
        updated["private_token"] = token
        let json = try JSONEncoder().encode(updated)
        guard try run(
            "UPDATE sources SET config = ? WHERE id = ?",
            [String(decoding: json, as: UTF8.self), id]
        ) > 0 else {
            throw AppError.notFound("Source")
        }
    }

    func updateSourceConfig(id: Int64, config: [String: String]) throws {
        let json = try JSONEncoder().encode(config)
        guard try run(
            "UPDATE sources SET config = ? WHERE id = ?",
            [String(decoding: json, as: UTF8.self), id]
        ) > 0 else {
            throw AppError.notFound("Source")
        }
    }

    func deleteSource(id: Int64) throws {
        guard try run("DELETE FROM sources WHERE id = ?", [id]) > 0 else {
            throw AppError.notFound("Source")
        }
    }

    // ── Saved credentials ──

    func listCredentials() throws -> [SavedCredential] {
        try rows("SELECT id, name, kind, data FROM credentials ORDER BY name, id") {
            (id: sqlite3_column_int64($0, 0), name: self.text($0, 1), kind: self.text($0, 2), data: self.text($0, 3))
        }.compactMap { row in
            guard let kind = CredentialKind(rawValue: row.kind),
                  let bytes = row.data.data(using: .utf8),
                  let data = try? JSONDecoder().decode([String: String].self, from: bytes) else { return nil }
            return SavedCredential(id: row.id, name: row.name, kind: kind, data: data)
        }
    }

    func createCredential(name: String, kind: CredentialKind, data: [String: String]) throws -> Int64 {
        let json = try JSONEncoder().encode(data)
        try run(
            "INSERT INTO credentials (name, kind, data, created_at) VALUES (?, ?, ?, ?)",
            [name, kind.rawValue, String(decoding: json, as: UTF8.self), now()]
        )
        return sqlite3_last_insert_rowid(db)
    }

    func updateCredential(id: Int64, name: String, data: [String: String]) throws {
        let json = try JSONEncoder().encode(data)
        guard try run(
            "UPDATE credentials SET name = ?, data = ? WHERE id = ?",
            [name, String(decoding: json, as: UTF8.self), id]
        ) > 0 else {
            throw AppError.notFound("Credential")
        }
    }

    func deleteCredential(id: Int64) throws {
        guard try run("DELETE FROM credentials WHERE id = ?", [id]) > 0 else {
            throw AppError.notFound("Credential")
        }
    }

    func reorderSources(projectID: Int64, orderedIDs: [Int64]) throws {
        let total = try scalarInt("SELECT COUNT(*) FROM sources WHERE project_id = ?", [projectID])
        guard total == Int64(orderedIDs.count) else {
            throw AppError.db("ordered ids must contain every source in the project exactly once")
        }
        try inTransaction {
            for (index, id) in orderedIDs.enumerated() {
                guard try run(
                    "UPDATE sources SET sort_order = ? WHERE id = ? AND project_id = ?",
                    [Int64(index), id, projectID]
                ) > 0 else {
                    throw AppError.notFound("Source")
                }
            }
        }
    }
}
