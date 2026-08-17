import Foundation

/// Providers fetch and persist key/value variables in external services.
/// Dispatch mirrors providers/mod.rs.
enum Providers {
    static func getVariables(type: SourceType, config: [String: String]) async throws -> [Variable] {
        switch type {
        case .lambda: try await LambdaProvider.getVariables(config: config)
        case .gitlabCICD: try await GitLabProvider.getVariables(config: config)
        case .secretsManager: try await SecretsManagerProvider.getVariables(config: config)
        }
    }

    static func saveVariables(type: SourceType, config: [String: String], variables: [Variable]) async throws {
        switch type {
        case .lambda: try await LambdaProvider.saveVariables(config: config, variables: variables)
        case .gitlabCICD: try await GitLabProvider.saveVariables(config: config, variables: variables)
        case .secretsManager: try await SecretsManagerProvider.saveVariables(config: config, variables: variables)
        }
    }

    static func requireField(_ config: [String: String], _ key: String) throws -> String {
        guard let value = config[key] else { throw AppError.missingConfigField(key) }
        return value
    }
}
