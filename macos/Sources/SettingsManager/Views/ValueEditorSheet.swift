import SwiftUI

struct ValueEditorSheet: View {
    let varKey: String
    let value: String
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: String
    @State private var lang: EditorLanguage
    @State private var formatError = ""

    init(varKey: String, value: String, onSave: @escaping (String) -> Void) {
        self.varKey = varKey
        self.value = value
        self.onSave = onSave
        _draft = State(initialValue: value)
        _lang = State(initialValue: CodeFormat.detectLang(value))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(varKey)
                    .font(.system(.title3, design: .monospaced).bold())
                Spacer()
                Picker("", selection: $lang) {
                    ForEach(EditorLanguage.allCases) { l in
                        Text(l.label).tag(l)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
                Button("Format") {
                    do {
                        draft = try CodeFormat.format(draft, lang: lang)
                        formatError = ""
                    } catch {
                        formatError = error.localizedDescription
                    }
                }
                SecretGeneratorButton {
                    draft = $0
                    formatError = ""
                }
            }

            if !formatError.isEmpty {
                Text(formatError).foregroundStyle(.red).font(.callout)
            }

            CodeEditor(text: Binding(
                get: { draft },
                set: { draft = $0; if !formatError.isEmpty { formatError = "" } }
            ), lang: lang)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    onSave(draft)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 700, height: 520)
    }
}
