import Foundation
import Security

/// Port of lib/generate.ts — cryptographically random secrets with
/// rejection sampling to avoid modulo bias.
enum SecretGen {
    enum Kind: String, CaseIterable, Identifiable {
        case apiKey, password, hex
        var id: String { rawValue }
    }

    struct Preset {
        let kind: Kind
        let label: String
        let length: Int
        let symbols: Bool
        let hasSymbols: Bool
    }

    static let presets: [Preset] = [
        Preset(kind: .apiKey, label: "API key", length: 32, symbols: false, hasSymbols: false),
        Preset(kind: .password, label: "Password", length: 20, symbols: true, hasSymbols: true),
        Preset(kind: .hex, label: "Hex token", length: 64, symbols: false, hasSymbols: false),
    ]

    static let minLength = 8
    static let maxLength = 128

    private static let alphanumeric = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
    // Symbols that are safe in shell/env-file contexts (no quotes, spaces, or backslash).
    private static let symbols = Array("!#$%&*+-=?@^_")
    private static let hex = Array("0123456789abcdef")

    private static func charset(for kind: Kind, symbols useSymbols: Bool) -> [Character] {
        if kind == .hex { return hex }
        return useSymbols ? alphanumeric + symbols : alphanumeric
    }

    static func generate(kind: Kind, length: Int, symbols useSymbols: Bool = false) -> String {
        let charset = charset(for: kind, symbols: useSymbols)
        let n = charset.count
        // Discard bytes above the largest whole multiple of the charset size,
        // avoiding the bias a plain `byte % n` would introduce.
        let limit = (256 / n) * n
        var out: [Character] = []
        var buffer = [UInt8](repeating: 0, count: max(length, 16))

        while out.count < length {
            guard SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer) == errSecSuccess else {
                // SecRandom failing is effectively impossible; fall back to the
                // system RNG rather than returning a weak or empty secret.
                var rng = SystemRandomNumberGenerator()
                return String((0..<length).map { _ in charset.randomElement(using: &rng)! })
            }
            for byte in buffer where out.count < length {
                if Int(byte) < limit { out.append(charset[Int(byte) % n]) }
            }
        }
        return String(out)
    }
}
