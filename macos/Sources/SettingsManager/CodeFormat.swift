import Foundation
import Yams
import TOMLKit

/// Port of lib/codeEditor.ts.
enum EditorLanguage: String, CaseIterable, Identifiable {
    case yaml
    case toml
    case json
    case text

    var id: String { rawValue }

    var label: String {
        switch self {
        case .yaml: "YAML"
        case .toml: "TOML"
        case .json: "JSON"
        case .text: "Plain"
        }
    }
}

enum CodeFormat {
    static func detectLang(_ value: String) -> EditorLanguage {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) || (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")) {
            if let data = trimmed.data(using: .utf8),
               (try? JSONSerialization.jsonObject(with: data)) != nil {
                return .json
            }
        }
        if matches(value, #"^---(\n|$)"#) || matches(value, #"(?m)^\w[\w.-]*:\s+\S"#) {
            return .yaml
        }
        if matches(value, #"(?m)^\[[\w.-]+\]"#) || matches(value, #"(?m)^\w[\w.-]*\s*=\s*\S"#) {
            return .toml
        }
        return .text
    }

    private static func matches(_ value: String, _ pattern: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }

    static func format(_ value: String, lang: EditorLanguage) throws -> String {
        guard !value.isEmpty else { return "" }
        switch lang {
        case .yaml:
            // compose/serialize round-trips the node tree, preserving key order
            // (Yams.load would lose it in a Dictionary).
            do {
                guard let node = try Yams.compose(yaml: value) else { return "" }
                return try Yams.serialize(node: node)
            } catch {
                throw formatError("Invalid YAML: \(error.localizedDescription)")
            }
        case .toml:
            // ponytail: no numeric-separator stripping (the TS port needed it for
            // @iarna/toml output); TOMLKit doesn't emit `_` separators.
            do {
                return try TOMLTable(string: value).convert()
            } catch {
                throw formatError("Invalid TOML: \(error.localizedDescription)")
            }
        case .json:
            guard let data = value.data(using: .utf8) else { throw AppError.http("invalid encoding") }
            let object: Any
            do {
                object = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
            } catch {
                throw formatError("Invalid JSON: \(error.localizedDescription)")
            }
            let pretty = try JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]
            )
            return String(decoding: pretty, as: UTF8.self) + "\n"
        case .text:
            return normalizePlainText(value)
        }
    }

    private static func formatError(_ message: String) -> NSError {
        NSError(domain: "CodeFormat", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private static func normalizePlainText(_ value: String) -> String {
        let normalized = value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                var s = String(line)
                while s.hasSuffix(" ") || s.hasSuffix("\t") { s.removeLast() }
                return s
            }
            .joined(separator: "\n")

        if !normalized.isEmpty, normalized.contains("\n"), !normalized.hasSuffix("\n") {
            return normalized + "\n"
        }
        return normalized
    }
}
