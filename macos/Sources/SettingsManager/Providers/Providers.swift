import Foundation

/// Payload format of a Secrets Manager secret. Detected on fetch and reused
/// on save so the secret round-trips in its original format.
enum SecretFormat: String, Codable {
    case json
    case toml
    case yaml
    case dotenv
    case plaintext
}

/// Fetch result: variables plus the detected secret format (Secrets Manager
/// only, nil for other providers).
struct FetchResult: Encodable {
    var variables: [Variable]
    var secretFormat: SecretFormat?
}

/// Providers fetch and persist key/value variables in external services.
/// Dispatch mirrors providers/mod.rs.
enum Providers {
    static func getVariables(type: SourceType, config: [String: String]) async throws -> FetchResult {
        switch type {
        case .lambda:
            FetchResult(variables: try await LambdaProvider.getVariables(config: config))
        case .gitlabCICD:
            FetchResult(variables: try await GitLabProvider.getVariables(config: config))
        case .secretsManager:
            try await SecretsManagerProvider.getVariables(config: config)
        }
    }

    static func saveVariables(
        type: SourceType,
        config: [String: String],
        variables: [Variable],
        secretFormat: SecretFormat? = nil
    ) async throws {
        switch type {
        case .lambda:
            try await LambdaProvider.saveVariables(config: config, variables: variables)
        case .gitlabCICD:
            try await GitLabProvider.saveVariables(config: config, variables: variables)
        case .secretsManager:
            try await SecretsManagerProvider.saveVariables(
                config: config, variables: variables, format: secretFormat ?? .json
            )
        }
    }

    static func requireField(_ config: [String: String], _ key: String) throws -> String {
        guard let value = config[key] else { throw AppError.missingConfigField(key) }
        return value
    }
}
