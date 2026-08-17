import Foundation
import AWSLambda
import AWSSecretsManager
import AWSSDKIdentity
import SmithyIdentity

/// Builds a static-credentials resolver from the source config
/// (port of aws_sdk_config in providers/mod.rs).
private func credentials(_ config: [String: String]) throws -> (resolver: StaticAWSCredentialIdentityResolver, region: String) {
    let accessKey = try Providers.requireField(config, "aws_access_key_id")
    let secretKey = try Providers.requireField(config, "aws_secret_access_key")
    let region = try Providers.requireField(config, "aws_region")
    let creds = AWSCredentialIdentity(accessKey: accessKey, secret: secretKey)
    return (StaticAWSCredentialIdentityResolver(creds), region)
}

/// AWS Lambda environment variables provider.
enum LambdaProvider {
    private static func client(_ config: [String: String]) async throws -> (LambdaClient, String) {
        let functionName = try Providers.requireField(config, "function_name")
        let (resolver, region) = try credentials(config)
        let clientConfig = try await LambdaClient.LambdaClientConfig(
            awsCredentialIdentityResolver: resolver,
            region: region
        )
        return (LambdaClient(config: clientConfig), functionName)
    }

    static func getVariables(config: [String: String]) async throws -> [Variable] {
        let (client, functionName) = try await client(config)
        do {
            let resp = try await client.getFunctionConfiguration(
                input: GetFunctionConfigurationInput(functionName: functionName)
            )
            let map = resp.environment?.variables ?? [:]
            return map.map { Variable.kv($0.key, $0.value) }.sorted { $0.key < $1.key }
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.lambda(String(describing: error))
        }
    }

    static func saveVariables(config: [String: String], variables: [Variable]) async throws {
        let (client, functionName) = try await client(config)
        let map = Dictionary(variables.map { ($0.key, $0.value) }, uniquingKeysWith: { _, last in last })
        do {
            _ = try await client.updateFunctionConfiguration(
                input: UpdateFunctionConfigurationInput(
                    environment: LambdaClientTypes.Environment(variables: map),
                    functionName: functionName
                )
            )
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.lambda(String(describing: error))
        }
    }
}

/// AWS Secrets Manager provider. One secret holds all variables as a JSON
/// object of key/value pairs — the standard Secrets Manager key/value layout.
enum SecretsManagerProvider {
    private static func client(_ config: [String: String]) async throws -> (SecretsManagerClient, String) {
        let secretName = try Providers.requireField(config, "secret_name")
        let (resolver, region) = try credentials(config)
        let clientConfig = try await SecretsManagerClient.SecretsManagerClientConfig(
            awsCredentialIdentityResolver: resolver,
            region: region
        )
        return (SecretsManagerClient(config: clientConfig), secretName)
    }

    /// Parses a secret payload into sorted variables. Non-string JSON values
    /// are kept as their JSON representation.
    static func parseSecretMap(_ secretString: String) throws -> [Variable] {
        guard let data = secretString.data(using: .utf8),
              let map = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AppError.secretNotJsonObject
        }
        return map.map { key, value in
            if let s = value as? String { return Variable.kv(key, s) }
            let json = (try? JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed))
                .map { String(decoding: $0, as: UTF8.self) }
            return Variable.kv(key, json ?? String(describing: value))
        }.sorted { $0.key < $1.key }
    }

    static func getVariables(config: [String: String]) async throws -> [Variable] {
        let (client, secretName) = try await client(config)
        do {
            let resp = try await client.getSecretValue(input: GetSecretValueInput(secretId: secretName))
            return try parseSecretMap(resp.secretString ?? "{}")
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.secretsManager(String(describing: error))
        }
    }

    static func saveVariables(config: [String: String], variables: [Variable]) async throws {
        let (client, secretName) = try await client(config)
        let map = Dictionary(variables.map { ($0.key, $0.value) }, uniquingKeysWith: { _, last in last })
        let json = try JSONSerialization.data(withJSONObject: map, options: .sortedKeys)
        do {
            _ = try await client.putSecretValue(
                input: PutSecretValueInput(
                    secretId: secretName,
                    secretString: String(decoding: json, as: UTF8.self)
                )
            )
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.secretsManager(String(describing: error))
        }
    }
}
