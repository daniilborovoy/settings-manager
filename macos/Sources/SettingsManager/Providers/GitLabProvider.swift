import Foundation

/// GitLab CI/CD project variables provider.
///
/// Saving diffs the desired state against the live one: removed variables are
/// deleted, the rest are created or updated. A variable's identity is the
/// `(key, environment_scope)` pair.
enum GitLabProvider {
    private static let perPage = 100

    // Self-hosted GitLab instances frequently run on self-signed certificates
    // (mirrors reqwest's danger_accept_invalid_certs in the Tauri backend).
    private final class TrustAnyCertDelegate: NSObject, URLSessionDelegate {
        func urlSession(
            _ session: URLSession,
            didReceive challenge: URLAuthenticationChallenge,
            completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
            if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
               let trust = challenge.protectionSpace.serverTrust {
                completionHandler(.useCredential, URLCredential(trust: trust))
            } else {
                completionHandler(.performDefaultHandling, nil)
            }
        }
    }

    private static let session = URLSession(
        configuration: .ephemeral,
        delegate: TrustAnyCertDelegate(),
        delegateQueue: nil
    )

    private static func encodePathComponent(_ value: String) -> String {
        // Match urlencoding::encode: keep only unreserved characters, so "/" in
        // "namespace/project" becomes %2F.
        let unreserved = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }

    private static func baseURL(config: [String: String]) throws -> String {
        var gitlabURL = try Providers.requireField(config, "gitlab_url")
        while gitlabURL.hasSuffix("/") { gitlabURL.removeLast() }
        let projectID = try Providers.requireField(config, "project_id")
        return "\(gitlabURL)/api/v4/projects/\(encodePathComponent(projectID))/variables"
    }

    /// Pulls a human-readable message out of a GitLab error body, which may be
    /// {"message": "..."}, {"message": {field: [msgs]}}, or {"error": "..."}.
    static func extractError(_ body: String) -> String {
        guard let data = body.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return body
        }
        if let message = parsed["message"] {
            if let s = message as? String { return s }
            if let obj = message as? [String: Any] {
                return obj.sorted { $0.key < $1.key }.map { field, messages in
                    if let arr = messages as? [Any] {
                        return "\(field): \(arr.compactMap { $0 as? String }.joined(separator: ", "))"
                    }
                    return "\(field): \(messages)"
                }.joined(separator: "; ")
            }
            return String(describing: message)
        }
        if let error = parsed["error"] as? String { return error }
        return body
    }

    private static func request(
        _ method: String,
        _ url: String,
        token: String,
        query: [URLQueryItem] = [],
        body: [String: Any]? = nil,
        context: String? = nil
    ) async throws -> Data {
        guard var components = URLComponents(string: url) else { throw AppError.http("bad URL: \(url)") }
        if !query.isEmpty { components.queryItems = query }
        guard let finalURL = components.url else { throw AppError.http("bad URL: \(url)") }

        var req = URLRequest(url: finalURL)
        req.httpMethod = method
        req.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw AppError.http(error.localizedDescription)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            var message = extractError(String(decoding: data, as: UTF8.self))
            if let context { message += " (\(context))" }
            throw AppError.gitlab(status: status, message: message)
        }
        return data
    }

    private static func identity(_ v: Variable) -> String {
        "\(v.key)\u{0}\(v.environmentScope ?? "*")"
    }

    private static func body(for v: Variable) -> [String: Any] {
        var obj: [String: Any] = ["key": v.key, "value": v.value]
        if let t = v.variableType { obj["variable_type"] = t }
        if let s = v.environmentScope { obj["environment_scope"] = s }
        if let p = v.protected { obj["protected"] = p }
        if let m = v.masked { obj["masked"] = m }
        // The API field for creating a hidden variable is `masked_and_hidden`,
        // while reads report it back as `hidden`.
        if let h = v.hidden { obj["masked_and_hidden"] = h }
        if let r = v.raw { obj["raw"] = r }
        if let d = v.description { obj["description"] = d }
        return obj
    }

    static func getVariables(config: [String: String]) async throws -> [Variable] {
        let url = try baseURL(config: config)
        let token = try Providers.requireField(config, "private_token")

        var out: [Variable] = []
        var page = 1
        while true {
            let data = try await request(
                "GET", url, token: token,
                query: [
                    URLQueryItem(name: "per_page", value: String(perPage)),
                    URLQueryItem(name: "page", value: String(page)),
                ]
            )
            let batch = try JSONDecoder().decode([Variable].self, from: data)
            out.append(contentsOf: batch)
            if batch.count < perPage { break }
            page += 1
        }
        return out
    }

    static func saveVariables(config: [String: String], variables newVars: [Variable]) async throws {
        let url = try baseURL(config: config)
        let token = try Providers.requireField(config, "private_token")

        let existing = try await getVariables(config: config)
        let existingSet = Set(existing.map(identity))
        let newSet = Set(newVars.map(identity))

        for old in existing where !newSet.contains(identity(old)) {
            let scope = old.environmentScope ?? "*"
            _ = try await request(
                "DELETE", "\(url)/\(encodePathComponent(old.key))", token: token,
                query: [URLQueryItem(name: "filter[environment_scope]", value: scope)],
                context: "while deleting \(old.key):\(scope)"
            )
        }

        for newVar in newVars {
            let scope = newVar.environmentScope ?? "*"
            if existingSet.contains(identity(newVar)) {
                _ = try await request(
                    "PUT", "\(url)/\(encodePathComponent(newVar.key))", token: token,
                    query: [URLQueryItem(name: "filter[environment_scope]", value: scope)],
                    body: body(for: newVar),
                    context: "while updating \(newVar.key):\(scope)"
                )
            } else {
                _ = try await request(
                    "POST", url, token: token,
                    body: body(for: newVar),
                    context: "while creating \(newVar.key):\(scope)"
                )
            }
        }
    }
}
