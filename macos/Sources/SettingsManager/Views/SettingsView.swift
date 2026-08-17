import SwiftUI

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @AppStorage("theme") private var theme = "system"
    @State private var editingCredential: SavedCredential?
    @State private var addingCredential = false
    @State private var deleteCandidate: SavedCredential?

    var body: some View {
        Form {
            Section("Design") {
                Picker("Appearance", selection: $theme) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
                Text("Switch between light and dark color schemes.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("API Keys") {
                if store.credentials.isEmpty {
                    Text("No saved keys yet. Keys you enter when adding a source are saved here automatically.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach(store.credentials) { cred in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(cred.name)
                            Text("\(cred.kind.label) · \(cred.hint)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Edit") { editingCredential = cred }
                        Button(role: .destructive) {
                            deleteCandidate = cred
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
                Button("Add Key...") { addingCredential = true }
                Text("Sources keep their own copy of a key — deleting one here never breaks a source.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 560, alignment: .leading)
        .navigationTitle("Settings")
        .sheet(item: $editingCredential) { CredentialSheet(existing: $0) }
        .sheet(isPresented: $addingCredential) { CredentialSheet(existing: nil) }
        .confirmationDialog(
            "Delete key \"\(deleteCandidate?.name ?? "")\"?",
            isPresented: Binding(get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } }),
            titleVisibility: .visible,
            presenting: deleteCandidate
        ) { cred in
            Button("Delete", role: .destructive) { store.deleteCredential(id: cred.id) }
            Button("Cancel", role: .cancel) {}
        }
    }
}

/// Create or edit a saved credential.
struct CredentialSheet: View {
    let existing: SavedCredential?

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var kind: CredentialKind
    @State private var data: [String: String]
    @State private var error: String?
    @State private var loading = false

    init(existing: SavedCredential?) {
        self.existing = existing
        _name = State(initialValue: existing?.name ?? "")
        _kind = State(initialValue: existing?.kind ?? .aws)
        _data = State(initialValue: existing?.data ?? [:])
    }

    private func fieldLabel(_ field: String) -> String {
        switch field {
        case "aws_access_key_id": "Access Key ID"
        case "aws_secret_access_key": "Secret Access Key"
        default: "Private Token"
        }
    }

    private var isComplete: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && kind.fields.allSatisfy { !(data[$0] ?? "").isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(existing == nil ? "Add Key" : "Edit Key").font(.title3.bold())

            LabeledContent("Name") {
                TextField("", text: $name, prompt: Text("Prod AWS, Personal GitLab, ..."))
                    .textFieldStyle(.roundedBorder)
            }
            if existing == nil {
                LabeledContent("Type") {
                    Picker("", selection: $kind) {
                        ForEach(CredentialKind.allCases) { k in
                            Text(k.label).tag(k)
                        }
                    }
                    .labelsHidden()
                    .onChange(of: kind) { _, _ in data = [:] }
                }
            }
            ForEach(kind.fields, id: \.self) { field in
                LabeledContent(fieldLabel(field)) {
                    let binding = Binding(
                        get: { data[field] ?? "" },
                        set: { data[field] = $0 }
                    )
                    if field == "aws_access_key_id" {
                        TextField("", text: binding, prompt: Text("AKIAIOSFODNN7EXAMPLE"))
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("", text: binding, prompt: Text("••••••••"))
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }

            if let error {
                Text(error).foregroundStyle(.red).font(.callout).textSelection(.enabled)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button(loading ? "Saving..." : "Save", action: submit)
                    .buttonStyle(.borderedProminent)
                    .disabled(loading || !isComplete)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func submit() {
        error = nil
        loading = true
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedData = data.mapValues { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        Task {
            do {
                if let existing {
                    try await store.updateCredential(id: existing.id, name: trimmedName, data: trimmedData)
                } else {
                    try await store.createCredential(name: trimmedName, kind: kind, data: trimmedData)
                }
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            loading = false
        }
    }
}
