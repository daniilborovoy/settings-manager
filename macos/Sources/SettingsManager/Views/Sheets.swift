import SwiftUI

// ── Add Project ──

struct AddProjectSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var error: String?
    @State private var loading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Project").font(.title3.bold())
            TextField("Name", text: $name, prompt: Text("Backend, Mobile, ..."))
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)
            if let error {
                Text(error).foregroundStyle(.red).font(.callout)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button(loading ? "Creating..." : "Create Project", action: submit)
                    .buttonStyle(.borderedProminent)
                    .disabled(loading || name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func submit() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        error = nil
        loading = true
        Task {
            do {
                try await store.createProject(name: trimmed)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            loading = false
        }
    }
}

// ── Add Source ──

private struct SourceField {
    let key: String
    let label: String
    let placeholder: String
    let secure: Bool

    init(_ key: String, _ label: String, _ placeholder: String, secure: Bool = false) {
        self.key = key
        self.label = label
        self.placeholder = placeholder
        self.secure = secure
    }
}

private func fields(for type: SourceType) -> [SourceField] {
    switch type {
    case .lambda: [
        SourceField("function_name", "Function Name", "your-function-name"),
        SourceField("aws_region", "AWS Region", "eu-west-1"),
        SourceField("aws_access_key_id", "AWS Access Key ID", "AKIAIOSFODNN7EXAMPLE"),
        SourceField("aws_secret_access_key", "AWS Secret Access Key", "••••••••", secure: true),
    ]
    case .secretsManager: [
        SourceField("secret_name", "Secret Name or ARN", "my-app/prod"),
        SourceField("aws_region", "AWS Region", "eu-west-1"),
        SourceField("aws_access_key_id", "AWS Access Key ID", "AKIAIOSFODNN7EXAMPLE"),
        SourceField("aws_secret_access_key", "AWS Secret Access Key", "••••••••", secure: true),
    ]
    case .gitlabCICD: [
        SourceField("gitlab_url", "GitLab URL", "https://gitlab.company.com"),
        SourceField("project_id", "Project ID or Path", "123 or namespace/project"),
        SourceField("private_token", "Private Token", "glpat-••••••••", secure: true),
    ]
    }
}

struct AddSourceSheet: View {
    let project: Project

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var type: SourceType = .lambda
    @State private var config: [String: String] = [:]
    @State private var error: String?
    @State private var loading = false

    private var isComplete: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && fields(for: type).allSatisfy { !(config[$0.key] ?? "").isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Source to \(project.name)").font(.title3.bold())

            LabeledContent("Name") {
                TextField("", text: $name, prompt: Text("My Lambda / My GitLab Project"))
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("Type") {
                Picker("", selection: $type) {
                    ForEach(SourceType.allCases) { t in
                        Text(t.label).tag(t)
                    }
                }
                .labelsHidden()
                .onChange(of: type) { _, _ in config = [:] }
            }
            ForEach(fields(for: type), id: \.key) { field in
                LabeledContent(field.label) {
                    let binding = Binding(
                        get: { config[field.key] ?? "" },
                        set: { config[field.key] = $0 }
                    )
                    if field.secure {
                        SecureField("", text: binding, prompt: Text(field.placeholder))
                            .textFieldStyle(.roundedBorder)
                    } else {
                        TextField("", text: binding, prompt: Text(field.placeholder))
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
                Button(loading ? "Adding..." : "Add Source", action: submit)
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
        Task {
            do {
                try await store.createSource(
                    projectID: project.id,
                    name: name.trimmingCharacters(in: .whitespaces),
                    type: type,
                    // Pasted credentials often carry stray whitespace/newlines.
                    config: config.mapValues { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                )
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            loading = false
        }
    }
}

// ── Edit Source config ──

struct EditSourceSheet: View {
    let source: Source

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var config: [String: String] = [:]
    @State private var error: String?
    @State private var loading = false

    private var isComplete: Bool {
        fields(for: source.type).allSatisfy { !(config[$0.key] ?? "").isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit \(source.name)").font(.title3.bold())
            Text(source.type.label)
                .font(.callout)
                .foregroundStyle(.secondary)

            ForEach(fields(for: source.type), id: \.key) { field in
                LabeledContent(field.label) {
                    let binding = Binding(
                        get: { config[field.key] ?? "" },
                        set: { config[field.key] = $0 }
                    )
                    if field.secure {
                        SecureField("", text: binding, prompt: Text(field.placeholder))
                            .textFieldStyle(.roundedBorder)
                    } else {
                        TextField("", text: binding, prompt: Text(field.placeholder))
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
        .onAppear { config = store.sourceConfig(id: source.id) }
    }

    private func submit() {
        error = nil
        loading = true
        Task {
            do {
                try await store.updateSourceConfig(
                    id: source.id,
                    config: config.mapValues { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                )
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            loading = false
        }
    }
}

// ── Update GitLab token ──

struct UpdateTokenSheet: View {
    let prompt: TokenPrompt

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var token = ""
    @State private var error: String?
    @State private var loading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("GitLab token expired").font(.title3.bold())
            Text("GitLab rejected the token for \"\(prompt.source.name)\" (401 Unauthorized). Enter a new private token to continue.")
                .font(.callout)
                .foregroundStyle(.secondary)
            SecureField("New Private Token", text: $token, prompt: Text("glpat-••••••••"))
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)
            if let error {
                Text(error).foregroundStyle(.red).font(.callout).textSelection(.enabled)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button(loading ? "Updating..." : "Update Token", action: submit)
                    .buttonStyle(.borderedProminent)
                    .disabled(loading || token.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func submit() {
        let trimmed = token.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        error = nil
        loading = true
        Task {
            do {
                try await store.submitToken(prompt: prompt, token: trimmed)
                dismiss()
            } catch {
                // A repeated 401 (or any failure) keeps the sheet open.
                self.error = error.localizedDescription
            }
            loading = false
        }
    }
}
