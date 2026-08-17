import Foundation
import AWSLambda
import AWSSecretsManager
import AWSSDKIdentity
import SmithyIdentity
import ClientRuntime
import Yams
import TOMLKit

/// Human-readable message instead of dumping the whole error struct
/// (UnknownAWSHTTPServiceError(typeName: Optional(...), ...)).
private func awsMessage(_ error: Error) -> String {
    if let service = error as? ServiceError {
        let type = service.typeName ?? "AWSError"
        let message = service.message ?? ""
        return message.isEmpty ? type : "\(type): \(message)"
    }
    return String(describing: error)
}

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
            throw AppError.lambda(awsMessage(error))
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
            throw AppError.lambda(awsMessage(error))
        }
    }
}

/// AWS Secrets Manager provider. The secret payload may be a JSON object,
/// TOML, YAML mapping, dotenv lines, or plain text; the detected format is
/// carried through FetchResult so saves round-trip in the same format.
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

    // ── Parsing ──

    /// Detection order: JSON object → TOML → YAML mapping → dotenv → plaintext.
    /// (dotenv lines are not valid TOML — unquoted values don't parse — and
    /// compose to a YAML scalar, not a mapping, so the order is safe.)
    static func parseSecret(_ raw: String) -> (variables: [Variable], format: SecretFormat) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return ([], .json) }

        if let data = trimmed.data(using: .utf8),
           let map = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            let vars = map.map { key, value -> Variable in
                if let s = value as? String { return Variable.kv(key, s) }
                let json = (try? JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed))
                    .map { String(decoding: $0, as: UTF8.self) }
                return Variable.kv(key, json ?? String(describing: value))
            }
            return (vars.sorted { $0.key < $1.key }, .json)
        }

        if let table = try? TOMLTable(string: raw) {
            let vars = table.keys.map { key -> Variable in
                // ponytail: non-string TOML values print via their description;
                // nested tables come out as inline TOML.
                if let s = table[key]?.string ?? nil { return Variable.kv(key, s) }
                return Variable.kv(key, table[key].map { String(describing: $0) } ?? "")
            }
            return (vars.sorted { $0.key < $1.key }, .toml)
        }

        if let node = try? Yams.compose(yaml: raw), case .mapping(let mapping) = node {
            let vars = mapping.map { key, value -> Variable in
                let k = key.string ?? String(describing: key)
                if let s = value.string { return Variable.kv(k, s) }
                let dumped = (try? Yams.serialize(node: value))?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return Variable.kv(k, dumped ?? "")
            }
            return (vars.sorted { $0.key < $1.key }, .yaml)
        }

        if let vars = parseDotenv(raw) {
            return (vars, .dotenv)
        }

        return ([Variable.kv("value", raw)], .plaintext)
    }

    /// Every non-empty, non-comment line must be KEY=VALUE, else nil.
    private static func parseDotenv(_ raw: String) -> [Variable]? {
        var vars: [Variable] = []
        for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t.hasPrefix("#") { continue }
            guard let eq = t.firstIndex(of: "=") else { return nil }
            var key = String(t[..<eq]).trimmingCharacters(in: .whitespaces)
            if key.hasPrefix("export ") {
                key = String(key.dropFirst("export ".count)).trimmingCharacters(in: .whitespaces)
            }
            guard !key.isEmpty else { return nil }
            var value = String(t[t.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if value.count >= 2,
               (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            vars.append(.kv(key, value))
        }
        return vars.isEmpty ? nil : vars
    }

    // ── Serialization ──

    static func serialize(_ variables: [Variable], format: SecretFormat) throws -> String {
        let map = Dictionary(variables.map { ($0.key, $0.value) }, uniquingKeysWith: { _, last in last })
        switch format {
        case .json:
            let json = try JSONSerialization.data(withJSONObject: map, options: .sortedKeys)
            return String(decoding: json, as: UTF8.self)
        case .toml:
            let table = TOMLTable()
            for (key, value) in map.sorted(by: { $0.key < $1.key }) { table[key] = value }
            return table.convert()
        case .yaml:
            let pairs = map.sorted { $0.key < $1.key }.map { (Node($0.key), Node($0.value)) }
            return try Yams.serialize(node: Node.mapping(Node.Mapping(pairs)))
        case .dotenv:
            // ponytail: values written raw — a value containing a newline needs
            // quoting this doesn't do.
            return variables.map { "\($0.key)=\($0.value)" }.joined(separator: "\n") + "\n"
        case .plaintext:
            // A single plaintext secret is just its value; extra rows degrade
            // to dotenv lines.
            if variables.count == 1 { return variables[0].value }
            return variables.map { "\($0.key)=\($0.value)" }.joined(separator: "\n") + "\n"
        }
    }

    // ── API ──

    static func getVariables(config: [String: String]) async throws -> FetchResult {
        let (client, secretName) = try await client(config)
        do {
            let resp = try await client.getSecretValue(input: GetSecretValueInput(secretId: secretName))
            let (vars, format) = parseSecret(resp.secretString ?? "{}")
            return FetchResult(variables: vars, secretFormat: format)
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.secretsManager(awsMessage(error))
        }
    }

    static func saveVariables(config: [String: String], variables: [Variable], format: SecretFormat) async throws {
        let (client, secretName) = try await client(config)
        let payload = try serialize(variables, format: format)
        do {
            _ = try await client.putSecretValue(
                input: PutSecretValueInput(secretId: secretName, secretString: payload)
            )
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.secretsManager(awsMessage(error))
        }
    }
}
