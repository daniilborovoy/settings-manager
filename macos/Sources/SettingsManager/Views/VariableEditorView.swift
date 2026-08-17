import SwiftUI

private struct EditingTarget: Identifiable {
    let index: Int
    let isNew: Bool
    var id: Int { index }
}

struct VariableEditorView: View {
    @Environment(AppStore.self) private var store
    @State private var search = ""
    @State private var showValues = false
    @State private var newKey = ""
    @State private var newValue = ""
    @State private var copyingFrom = false
    @State private var editing: EditingTarget?
    @State private var pendingNewIndex: Int?

    private var source: Source? { store.selectedSource }
    private var isGitlab: Bool { source?.type == .gitlabCICD }

    private var filteredIndices: [Int] {
        store.variables.indices.filter {
            search.isEmpty || store.variables[$0].key.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        if store.loadingVars {
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading variables...")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let source {
            editor(source)
        }
    }

    private func editor(_ source: Source) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(source)
            if let error = store.error {
                Text(error)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
            toolbar
            variableList
            Divider()
            addRow
        }
        .sheet(item: $editing, onDismiss: dropAbandonedNewVariable) { target in
            editorSheet(target)
        }
    }

    private func header(_ source: Source) -> some View {
        HStack(spacing: 12) {
            Text(source.name)
                .font(.title2.bold())
            Text("\(store.variables.count) variable\(store.variables.count == 1 ? "" : "s")")
                .foregroundStyle(.secondary)
            Spacer()
            if store.saveSuccess {
                Label("Saved successfully", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            }
            Button("Refresh") { store.refresh() }
            Button(store.saving ? "Saving..." : store.isDirty ? "Save Changes" : "No Changes") {
                Task { await store.save() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!store.isDirty || store.saving)
        }
        .padding(16)
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            TextField("Search variables...", text: $search)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 260)
            let others = store.allSources.filter { $0.source.id != source?.id }
            if !others.isEmpty {
                Menu(copyingFrom ? "Copying..." : "Copy from...") {
                    ForEach(others, id: \.source.id) { item in
                        Button("\(item.projectName) / \(item.source.name)") {
                            copyingFrom = true
                            Task {
                                await store.copyFrom(sourceID: item.source.id)
                                copyingFrom = false
                            }
                        }
                    }
                }
                .frame(maxWidth: 160)
                .disabled(copyingFrom)
            }
            Spacer()
            Button(showValues ? "Hide Values" : "Show Values") { showValues.toggle() }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var variableList: some View {
        List {
            if filteredIndices.isEmpty {
                Text(search.isEmpty ? "No variables yet" : "No variables match your search")
                    .foregroundStyle(.secondary)
            }
            ForEach(filteredIndices, id: \.self) { index in
                variableRow(index)
            }
        }
        .listStyle(.inset)
    }

    private func variableRow(_ index: Int) -> some View {
        let variable = store.variables[index]
        return HStack(spacing: 8) {
            if variable.key.isEmpty {
                Text("(unnamed)").italic().foregroundStyle(.secondary)
            } else {
                Text(variable.key)
                    .font(.system(.body, design: .monospaced))
            }
            if isGitlab {
                badges(variable)
            }
            Spacer()
            Button(isGitlab ? "Edit" : "Open") {
                editing = EditingTarget(index: index, isNew: false)
            }
            Button(role: .destructive) {
                deleteVariable(at: index)
            } label: {
                Image(systemName: "xmark")
            }
            .help("Delete variable")
        }
        .padding(.vertical, 2)
    }

    private func badges(_ v: Variable) -> some View {
        var labels: [String] = []
        if v.variableType == "file" { labels.append("file") }
        if v.protected == true { labels.append("protected") }
        if v.masked == true, v.hidden == true { labels.append("masked • hidden") }
        else if v.masked == true { labels.append("masked") }
        if v.raw == true { labels.append("raw") }
        if let scope = v.environmentScope, scope != "*" { labels.append("@\(scope)") }
        return HStack(spacing: 4) {
            ForEach(labels, id: \.self) { label in
                Text(label)
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var addRow: some View {
        if isGitlab {
            HStack(spacing: 12) {
                Button("+ Add variable") {
                    store.variables.append(.newGitlab())
                    pendingNewIndex = store.variables.count - 1
                    editing = EditingTarget(index: store.variables.count - 1, isNew: true)
                }
                Text("Use the full editor to set type, scope, and flags.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        } else {
            HStack(spacing: 8) {
                TextField("NEW_VARIABLE_KEY", text: $newKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit(quickAdd)
                Group {
                    if showValues {
                        TextField("value", text: $newValue)
                    } else {
                        SecureField("value", text: $newValue)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .onSubmit(quickAdd)
                Button("+ Add", action: quickAdd)
                    .disabled(newKey.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func editorSheet(_ target: EditingTarget) -> some View {
        if target.index < store.variables.count {
            let variable = store.variables[target.index]
            if isGitlab {
                GitlabVariableSheet(variable: variable, isNew: target.isNew) { next in
                    store.variables[target.index] = next
                }
            } else {
                ValueEditorSheet(varKey: variable.key, value: variable.value) { next in
                    store.variables[target.index].value = next
                }
            }
        }
    }

    private func quickAdd() {
        let key = newKey.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }
        store.variables.append(
            isGitlab ? .newGitlab(key: key, value: newValue) : .kv(key, newValue)
        )
        newKey = ""
        newValue = ""
    }

    private func deleteVariable(at index: Int) {
        guard index < store.variables.count else { return }
        store.variables.remove(at: index)
    }

    // A new gitlab variable that was cancelled without getting a key is dropped.
    private func dropAbandonedNewVariable() {
        defer { pendingNewIndex = nil }
        if let index = pendingNewIndex, index < store.variables.count,
           store.variables[index].key.isEmpty {
            store.variables.remove(at: index)
        }
    }
}
