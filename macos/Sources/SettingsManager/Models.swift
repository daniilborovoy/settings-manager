import Foundation

enum SourceType: String, Codable, CaseIterable, Identifiable {
    case lambda
    case gitlabCICD = "gitlab_cicd"
    case secretsManager = "secrets_manager"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .lambda: "AWS Lambda"
        case .gitlabCICD: "GitLab CI/CD"
        case .secretsManager: "AWS Secrets Manager"
        }
    }

    var badge: String {
        switch self {
        case .lambda: "λ Lambda"
        case .gitlabCICD: "⎇ GitLab CI/CD"
        case .secretsManager: "🔑 Secrets Manager"
        }
    }
}

struct Source: Identifiable, Hashable {
    let id: Int64
    var projectID: Int64
    var name: String
    var type: SourceType
}

struct Project: Identifiable, Hashable {
    let id: Int64
    var name: String
    var sources: [Source]
}

/// A single key/value variable. GitLab-specific metadata stays nil for plain
/// key/value providers (Lambda, Secrets Manager). `id` is UI identity only and
/// is excluded from coding; synthesized == includes it, which matches the
/// original dirty check (ids are shared between `variables` and
/// `originalVariables` until an edit replaces content).
struct Variable: Identifiable, Equatable, Codable {
    var id = UUID()
    var key: String
    var value: String
    var variableType: String?
    var environmentScope: String?
    var protected: Bool?
    var masked: Bool?
    var hidden: Bool?
    var raw: Bool?
    var description: String?

    enum CodingKeys: String, CodingKey {
        case key, value, protected, masked, hidden, raw, description
        case variableType = "variable_type"
        case environmentScope = "environment_scope"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        // GitLab omits or nulls `value` for hidden variables; treat both as empty.
        value = try c.decodeIfPresent(String.self, forKey: .value) ?? ""
        variableType = try c.decodeIfPresent(String.self, forKey: .variableType)
        environmentScope = try c.decodeIfPresent(String.self, forKey: .environmentScope)
        protected = try c.decodeIfPresent(Bool.self, forKey: .protected)
        masked = try c.decodeIfPresent(Bool.self, forKey: .masked)
        hidden = try c.decodeIfPresent(Bool.self, forKey: .hidden)
        raw = try c.decodeIfPresent(Bool.self, forKey: .raw)
        description = try c.decodeIfPresent(String.self, forKey: .description)
    }

    init(
        key: String = "",
        value: String = "",
        variableType: String? = nil,
        environmentScope: String? = nil,
        protected: Bool? = nil,
        masked: Bool? = nil,
        hidden: Bool? = nil,
        raw: Bool? = nil,
        description: String? = nil
    ) {
        self.key = key
        self.value = value
        self.variableType = variableType
        self.environmentScope = environmentScope
        self.protected = protected
        self.masked = masked
        self.hidden = hidden
        self.raw = raw
        self.description = description
    }

    static func kv(_ key: String, _ value: String) -> Variable {
        Variable(key: key, value: value)
    }

    static func newGitlab(key: String = "", value: String = "") -> Variable {
        Variable(
            key: key,
            value: value,
            variableType: "env_var",
            environmentScope: "*",
            protected: false,
            masked: false,
            hidden: false,
            raw: false
        )
    }
}

extension Array where Element == Variable {
    /// Port of normalizeForType: reshapes copied variables for the target source type.
    func normalized(for type: SourceType) -> [Variable] {
        switch type {
        case .gitlabCICD:
            return map { v in
                Variable(
                    key: v.key,
                    value: v.value,
                    variableType: v.variableType ?? "env_var",
                    environmentScope: v.environmentScope ?? "*",
                    protected: v.protected ?? false,
                    masked: v.masked ?? false,
                    hidden: v.hidden ?? false,
                    raw: v.raw ?? false,
                    description: v.description
                )
            }
        case .lambda, .secretsManager:
            return map { .kv($0.key, $0.value) }
        }
    }
}

/// Top-level error type; messages mirror the Rust `AppError`/`ProviderError`
/// Display strings (the UI matches on substrings like "401").
enum AppError: LocalizedError {
    case db(String)
    case notFound(String)
    case notGitlabSource
    case malformedConfig
    case missingConfigField(String)
    case gitlab(status: Int, message: String)
    case lambda(String)
    case secretsManager(String)
    case secretNotJsonObject
    case http(String)

    var errorDescription: String? {
        switch self {
        case .db(let m): "DB error: \(m)"
        case .notFound(let what): "\(what) not found"
        case .notGitlabSource: "Source is not a GitLab CI/CD source"
        case .malformedConfig: "Source config is malformed"
        case .missingConfigField(let f): "Missing config field: \(f)"
        case .gitlab(let status, let message): "GitLab \(status): \(message)"
        case .lambda(let m): "AWS Lambda: \(m)"
        case .secretsManager(let m): "AWS Secrets Manager: \(m)"
        case .secretNotJsonObject: "Secret value is not a JSON object of key/value pairs"
        case .http(let m): "Request failed: \(m)"
        }
    }
}
