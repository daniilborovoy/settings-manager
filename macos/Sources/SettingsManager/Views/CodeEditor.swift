import SwiftUI
import AppKit

/// Monospaced editor with lightweight JSON highlighting (replaces TextEditor
/// in the value sheets). Plain text renders uncolored.
/// ponytail: hand-rolled JSON tokenizer — swap in a highlighter package when more languages show up.
struct CodeEditor: NSViewRepresentable {
    @Binding var text: String
    var lang: EditorLanguage

    private static let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let textView = scroll.documentView as! NSTextView
        textView.delegate = context.coordinator
        textView.font = Self.font
        textView.isRichText = false
        textView.allowsUndo = true
        // Smart substitutions corrupt JSON quotes/dashes.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.string = text
        context.coordinator.highlight(textView, lang: lang)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        if textView.string != text {
            let selection = textView.selectedRange()
            textView.string = text
            let length = (text as NSString).length
            textView.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
        }
        context.coordinator.highlight(textView, lang: lang)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditor
        init(_ parent: CodeEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            highlight(textView, lang: parent.lang)
        }

        // Paint order matters: later rules override earlier ones, so numbers
        // and keywords go first, strings after them (covering anything matched
        // inside a string), then keys, and comments last.
        // ponytail: regex tokenizer, not a parser — a "#" inside a quoted YAML/TOML
        // string paints as comment; good enough for env values.
        private static func rule(_ pattern: String, _ color: NSColor) -> (NSRegularExpression, NSColor) {
            (try! NSRegularExpression(pattern: pattern), color)
        }

        private static let rules: [EditorLanguage: [(NSRegularExpression, NSColor)]] = [
            .json: [
                rule(#"-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?"#, .systemPurple),
                rule(#"\b(?:true|false|null)\b"#, .systemOrange),
                rule(#""(?:\\.|[^"\\])*""#, .systemRed),
                rule(#""(?:\\.|[^"\\])*"(?=\s*:)"#, .systemBlue),
            ],
            .yaml: [
                rule(#"-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?"#, .systemPurple),
                rule(#"\b(?:true|false|null|~)\b"#, .systemOrange),
                rule(#""(?:\\.|[^"\\])*"|'[^'\n]*'"#, .systemRed),
                rule(#"(?m)^[ \t]*(?:- )?[\w.-]+(?=[ \t]*:)"#, .systemBlue),
                rule(#"(?m)^---[ \t]*$"#, .secondaryLabelColor),
                rule(#"#[^\n]*"#, .secondaryLabelColor),
            ],
            .toml: [
                rule(#"-?\d[\d_]*(?:\.[\d_]+)?(?:[eE][+-]?\d+)?"#, .systemPurple),
                rule(#"\b(?:true|false)\b"#, .systemOrange),
                rule(#""(?:\\.|[^"\\])*"|'[^'\n]*'"#, .systemRed),
                rule(#"(?m)^[ \t]*[\w.-]+(?=[ \t]*=)"#, .systemBlue),
                rule(#"(?m)^[ \t]*\[\[?[\w.-]+\]?\]"#, .systemBlue),
                rule(#"#[^\n]*"#, .secondaryLabelColor),
            ],
        ]

        func highlight(_ textView: NSTextView, lang: EditorLanguage) {
            guard let storage = textView.textStorage else { return }
            let source = textView.string
            let full = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.setAttributes([.font: CodeEditor.font, .foregroundColor: NSColor.textColor], range: full)
            for (regex, color) in Self.rules[lang] ?? [] {
                regex.enumerateMatches(in: source, range: full) { match, _, _ in
                    guard let match else { return }
                    storage.addAttribute(.foregroundColor, value: color, range: match.range)
                }
            }
            storage.endEditing()
        }
    }
}
