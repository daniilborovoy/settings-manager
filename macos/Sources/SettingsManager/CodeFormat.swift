import Foundation

/// Port of lib/codeEditor.ts, minus CodeMirror.
/// ponytail: YAML/TOML formatting dropped — add Yams/TOMLKit when someone misses it.
enum EditorLanguage: String, CaseIterable, Identifiable {
    case json
    case text

    var id: String { rawValue }
    var label: String { self == .json ? "JSON" : "Plain" }
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
        return .text
    }

    static func format(_ value: String, lang: EditorLanguage) throws -> String {
        guard !value.isEmpty else { return "" }
        switch lang {
        case .json:
            guard let data = value.data(using: .utf8) else { throw AppError.http("invalid encoding") }
            let object: Any
            do {
                object = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
            } catch {
                throw NSError(
                    domain: "CodeFormat", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid JSON: \(error.localizedDescription)"]
                )
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
