import SwiftUI

private enum Visibility: String, CaseIterable, Identifiable {
    case visible, masked, maskedHidden
    var id: String { rawValue }
}

struct GitlabVariableSheet: View {
    let variable: Variable
    let isNew: Bool
    let onSave: (Variable) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: Variable
    @State private var lang: EditorLanguage
    @State private var formatError = ""

    init(variable: Variable, isNew: Bool, onSave: @escaping (Variable) -> Void) {
        self.variable = variable
        self.isNew = isNew
        self.onSave = onSave
        _draft = State(initialValue: variable)
        _lang = State(initialValue: CodeFormat.detectLang(variable.value))
    }

    private var visibility: Visibility {
        if draft.masked == true && draft.hidden == true { return .maskedHidden }
        if draft.masked == true { return .masked }
        return .visible
    }

    private func setVisibility(_ v: Visibility) {
        switch v {
        case .maskedHidden: draft.masked = true; draft.hidden = true
        case .masked: draft.masked = true; draft.hidden = false
        case .visible: draft.masked = false; draft.hidden = false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(isNew ? "Add variable" : "Edit variable")
                    .font(.title3.bold())
                Spacer()
            }

            HStack(spacing: 16) {
                Picker("Type", selection: Binding(
                    get: { draft.variableType ?? "env_var" },
                    set: { draft.variableType = $0 }
                )) {
                    Text("Variable").tag("env_var")
                    Text("File").tag("file")
                }
                .frame(maxWidth: 220)

                TextField("Environment scope", text: Binding(
                    get: { draft.environmentScope ?? "*" },
                    set: { draft.environmentScope = $0 }
                ), prompt: Text("* (All)"))
                .textFieldStyle(.roundedBorder)
            }

            Picker("Visibility", selection: Binding(get: { visibility }, set: setVisibility)) {
                Text("Visible — can be seen in job logs").tag(Visibility.visible)
                Text("Masked — masked in job logs, can be revealed in CI/CD settings").tag(Visibility.masked)
                Text(isNew
                     ? "Masked and hidden — can never be revealed again"
                     : "Masked and hidden — only configurable when creating a new variable")
                    .tag(Visibility.maskedHidden)
            }
            .pickerStyle(.radioGroup)
            // The masked+hidden option is create-only in the GitLab API.
            .onChange(of: visibility) { _, next in
                if next == .maskedHidden && !isNew { setVisibility(.masked) }
            }

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Protect variable — export only to pipelines on protected branches and tags", isOn: Binding(
                    get: { draft.protected ?? false },
                    set: { draft.protected = $0 }
                ))
                Toggle("Expand variable reference — $ starts a reference to another variable", isOn: Binding(
                    get: { !(draft.raw ?? false) },
                    set: { draft.raw = !$0 }
                ))
            }

            TextField("Description (optional)", text: Binding(
                get: { draft.description ?? "" },
                set: { draft.description = $0.isEmpty ? nil : $0 }
            ), prompt: Text("The description of the variable's value or usage."))
            .textFieldStyle(.roundedBorder)

            TextField("Key", text: $draft.key, prompt: Text("VARIABLE_KEY"))
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))

            HStack {
                Text("Value")
                Spacer()
                Picker("", selection: $lang) {
                    ForEach(EditorLanguage.allCases) { l in
                        Text(l.label).tag(l)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
                Button("Format") {
                    do {
                        draft.value = try CodeFormat.format(draft.value, lang: lang)
                        formatError = ""
                    } catch {
                        formatError = error.localizedDescription
                    }
                }
                SecretGeneratorButton { draft.value = $0 }
            }
            if !formatError.isEmpty {
                Text(formatError).foregroundStyle(.red).font(.callout)
            }
            TextEditor(text: Binding(
                get: { draft.value },
                set: { draft.value = $0; if !formatError.isEmpty { formatError = "" } }
            ))
            .font(.system(size: 13, design: .monospaced))
            .frame(minHeight: 160)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button(isNew ? "Add variable" : "Save changes") {
                    onSave(draft)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(draft.key.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 620, height: 640)
    }
}
