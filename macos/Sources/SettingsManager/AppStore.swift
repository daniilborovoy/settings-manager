import Foundation
import Observation

struct TokenPrompt: Identifiable {
    let source: Source
    let retry: @MainActor () async throws -> Void
    var id: Int64 { source.id }
}

/// Central app state — port of App.tsx state + the Tauri command layer.
/// The DB is local and fast, so its calls run synchronously on the main actor.
@MainActor
@Observable
final class AppStore {
    enum MainView { case sources, logs, settings }

    var projects: [Project] = []
    // Selection reactions run via .onChange in ContentView (didSet is not
    // reliable through a Bindable List(selection:) binding).
    var selectedSourceID: Int64?
    var variables: [Variable] = []
    var originalVariables: [Variable] = []
    var view: MainView = .sources
    var loadingVars = false
    var saving = false
    var error: String?
    var saveSuccess = false
    var expandedProjects: Set<Int64> = []

    // Sheet presentation
    var showAddProject = false
    var addSourceProject: Project?
    var tokenPrompt: TokenPrompt?

    let logs = LogStore()
    private let db: Database
    private var lastProjectCount = -1

    var selectedSource: Source? {
        guard let id = selectedSourceID else { return nil }
        return projects.lazy.flatMap(\.sources).first { $0.id == id }
    }

    var isDirty: Bool { variables != originalVariables }

    /// All sources with their project name, for the "Copy from…" menu.
    var allSources: [(source: Source, projectName: String)] {
        projects.flatMap { project in project.sources.map { ($0, project.name) } }
    }

    init() {
        do {
            let dir = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("com.settings-manager.app", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            db = try Database(path: dir.appendingPathComponent("settings_manager.db").path)
        } catch {
            // Keep the app usable enough to show the error.
            db = try! Database(path: ":memory:")
            self.error = (error as? AppError)?.errorDescription ?? error.localizedDescription
        }
        loadProjects()
    }

    // ── Logged call wrapper (port of api.ts `call`) ──

    private func logged<T>(
        _ command: String,
        args: [String: String]? = nil,
        _ op: @MainActor () async throws -> T
    ) async throws -> T {
        let start = Date()
        let argsJSON = args.flatMap { dict -> String? in
            let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
            return data.map { String(decoding: $0, as: UTF8.self) }
        }
        do {
            let result = try await op()
            logs.add(
                command: command, args: argsJSON, ok: true,
                durationMS: Int(Date().timeIntervalSince(start) * 1000),
                result: Self.describe(result)
            )
            return result
        } catch {
            let message = (error as? AppError)?.errorDescription ?? error.localizedDescription
            logs.add(
                command: command, args: argsJSON, ok: false,
                durationMS: Int(Date().timeIntervalSince(start) * 1000),
                error: message
            )
            throw error
        }
    }

    private nonisolated static func describe<T>(_ value: T) -> String? {
        if T.self == Void.self { return nil }
        if let encodable = value as? any Encodable {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(encodable) {
                return String(decoding: data, as: UTF8.self)
            }
        }
        return String(describing: value)
    }

    private func message(of error: Error) -> String {
        (error as? AppError)?.errorDescription ?? error.localizedDescription
    }

    // Credential values never go into the log page.
    private func redacted(_ config: [String: String]) -> [String: String] {
        let secretFields: Set<String> = ["private_token", "aws_secret_access_key", "token"]
        return config.reduce(into: [:]) { $0[$1.key] = secretFields.contains($1.key) ? "•••" : $1.value }
    }

    // ── Projects ──

    func loadProjects() {
        do {
            projects = try db.listProjectsWithSources()
        } catch {
            self.error = message(of: error)
            return
        }
        if projects.count != lastProjectCount {
            expandedProjects.formUnion(projects.map(\.id))
            lastProjectCount = projects.count
        }
        if selectedSourceID != nil, selectedSource == nil {
            selectedSourceID = nil
        }
    }

    func createProject(name: String) async throws {
        _ = try await logged("create_project", args: ["name": name]) {
            try db.createProject(name: name)
        }
        loadProjects()
    }

    func renameProject(id: Int64, name: String) {
        Task {
            try? await logged("rename_project", args: ["id": "\(id)", "name": name]) {
                try db.renameProject(id: id, name: name)
            }
            loadProjects()
        }
    }

    func deleteProject(id: Int64) {
        Task {
            try? await logged("delete_project", args: ["id": "\(id)"]) {
                try db.deleteProject(id: id)
            }
            loadProjects()
        }
    }

    func moveProjects(from: IndexSet, to: Int) {
        let previous = projects
        projects.move(fromOffsets: from, toOffset: to)
        let orderedIDs = projects.map(\.id)
        Task {
            do {
                try await logged("reorder_projects") { try db.reorderProjects(orderedIDs: orderedIDs) }
            } catch {
                projects = previous
            }
        }
    }

    // ── Sources ──

    func createSource(projectID: Int64, name: String, type: SourceType, config: [String: String]) async throws {
        var args = redacted(config)
        args["name"] = name
        args["type"] = type.rawValue
        _ = try await logged("create_source", args: args) {
            try db.createSource(projectID: projectID, name: name, type: type, config: config)
        }
        loadProjects()
    }

    func renameSource(id: Int64, name: String) {
        Task {
            try? await logged("rename_source", args: ["id": "\(id)", "name": name]) {
                try db.renameSource(id: id, name: name)
            }
            loadProjects()
        }
    }

    func deleteSource(id: Int64) {
        Task {
            try? await logged("delete_source", args: ["id": "\(id)"]) {
                try db.deleteSource(id: id)
            }
            if selectedSourceID == id { selectedSourceID = nil }
            loadProjects()
        }
    }

    func moveSources(projectID: Int64, from: IndexSet, to: Int) {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        let previous = projects
        projects[index].sources.move(fromOffsets: from, toOffset: to)
        let orderedIDs = projects[index].sources.map(\.id)
        Task {
            do {
                try await logged("reorder_sources") {
                    try db.reorderSources(projectID: projectID, orderedIDs: orderedIDs)
                }
            } catch {
                projects = previous
            }
        }
    }

    // ── Variables ──

    func sourceSelectionChanged() {
        if let id = selectedSourceID {
            view = .sources
            Task { await fetchVariables(sourceID: id) }
        } else {
            variables = []
            originalVariables = []
            error = nil
        }
    }

    func refresh() {
        guard let id = selectedSourceID else { return }
        Task { await fetchVariables(sourceID: id) }
    }

    func fetchVariables(sourceID: Int64) async {
        loadingVars = true
        error = nil
        saveSuccess = false

        // Throws on failure so the token sheet's retry can surface a repeated 401.
        let load: @MainActor () async throws -> Void = { [self] in
            let vars = try await logged("get_variables", args: ["id": "\(sourceID)"]) {
                let (type, config) = try db.sourceConfig(id: sourceID)
                return try await Providers.getVariables(type: type, config: config)
            }
            variables = vars
            originalVariables = vars
        }

        do {
            try await load()
        } catch {
            variables = []
            originalVariables = []
            let msg = message(of: error)
            if !maybePromptToken(message: msg, retry: load) { self.error = msg }
        }
        loadingVars = false
    }

    func save() async {
        guard let source = selectedSource else { return }
        saving = true
        error = nil
        saveSuccess = false

        let persist: @MainActor () async throws -> Void = { [self] in
            let toSave = variables
            try await logged("save_variables", args: ["id": "\(source.id)", "count": "\(toSave.count)"]) {
                let (type, config) = try db.sourceConfig(id: source.id)
                try await Providers.saveVariables(type: type, config: config, variables: toSave)
            }
            originalVariables = toSave
            saveSuccess = true
            Task {
                try? await Task.sleep(for: .seconds(3))
                saveSuccess = false
            }
        }

        do {
            try await persist()
        } catch {
            let msg = message(of: error)
            if !maybePromptToken(message: msg, retry: persist) { self.error = msg }
        }
        saving = false
    }

    /// Returns true when the failure is a GitLab auth error and the token sheet
    /// was opened. `retry` must throw on failure so a repeated 401 keeps it open.
    private func maybePromptToken(message: String, retry: @escaping @MainActor () async throws -> Void) -> Bool {
        guard let source = selectedSource, source.type == .gitlabCICD, message.contains("401") else {
            return false
        }
        error = nil
        tokenPrompt = TokenPrompt(source: source, retry: retry)
        return true
    }

    /// Called by the token sheet: persists the new token, then retries the
    /// operation that hit the 401. Throws so the sheet can stay open on failure.
    func submitToken(prompt: TokenPrompt, token: String) async throws {
        try await logged("update_gitlab_token", args: ["id": "\(prompt.source.id)", "token": "•••"]) {
            try db.updateGitlabToken(id: prompt.source.id, token: token)
        }
        try await prompt.retry()
    }

    func copyFrom(sourceID: Int64) async {
        guard let target = selectedSource else { return }
        do {
            let vars = try await logged("get_variables", args: ["id": "\(sourceID)"]) {
                let (type, config) = try db.sourceConfig(id: sourceID)
                return try await Providers.getVariables(type: type, config: config)
            }
            variables = vars.normalized(for: target.type)
        } catch {
            self.error = message(of: error)
        }
    }
}
