import SwiftUI

private enum RenameTarget: Identifiable {
    case project(Project)
    case source(Source)

    var id: String {
        switch self {
        case .project(let p): "project-\(p.id)"
        case .source(let s): "source-\(s.id)"
        }
    }

    var currentName: String {
        switch self {
        case .project(let p): p.name
        case .source(let s): s.name
        }
    }
}

private enum DeleteTarget: Identifiable {
    case project(Project)
    case source(Source)

    var id: String {
        switch self {
        case .project(let p): "project-\(p.id)"
        case .source(let s): "source-\(s.id)"
        }
    }
}

struct SidebarView: View {
    @Environment(AppStore.self) private var store
    @State private var renameTarget: RenameTarget?
    @State private var renameText = ""
    @State private var deleteTarget: DeleteTarget?

    var body: some View {
        @Bindable var store = store
        List(selection: $store.selectedSourceID) {
            if store.projects.isEmpty {
                Text("No projects yet.\nClick + to get started.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            ForEach(store.projects) { project in
                DisclosureGroup(isExpanded: expansionBinding(project.id)) {
                    ForEach(project.sources) { source in
                        sourceRow(source)
                    }
                    .onMove { from, to in
                        store.moveSources(projectID: project.id, from: from, to: to)
                    }
                    Button {
                        store.addSourceProject = project
                    } label: {
                        Label("Add Source", systemImage: "plus")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                } label: {
                    projectRow(project)
                }
            }
            .onMove { from, to in
                store.moveProjects(from: from, to: to)
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            Button {
                store.view = .sources
                store.showAddProject = true
            } label: {
                Label("Add Project", systemImage: "plus")
            }
            .help("Add Project")
        }
        .safeAreaInset(edge: .bottom) { footer }
        .alert(
            "Rename",
            isPresented: Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } }),
            presenting: renameTarget
        ) { target in
            TextField("Name", text: $renameText)
            Button("Save") { commitRename(target) }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            deleteMessage,
            isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
            titleVisibility: .visible,
            presenting: deleteTarget
        ) { target in
            Button("Delete", role: .destructive) { commitDelete(target) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var deleteMessage: String {
        switch deleteTarget {
        case .project(let p): "Delete project \"\(p.name)\" and all its sources?"
        case .source(let s): "Delete source \"\(s.name)\"?"
        case nil: ""
        }
    }

    private func expansionBinding(_ projectID: Int64) -> Binding<Bool> {
        Binding(
            get: { store.expandedProjects.contains(projectID) },
            set: { open in
                if open { store.expandedProjects.insert(projectID) }
                else { store.expandedProjects.remove(projectID) }
            }
        )
    }

    private func projectRow(_ project: Project) -> some View {
        HStack {
            Text(project.name)
                .fontWeight(.medium)
            Spacer()
            Text("\(project.sources.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(.quaternary, in: Capsule())
        }
        .contextMenu {
            Button("Rename") { startRename(.project(project)) }
            Button("Add Source") { store.addSourceProject = project }
            Divider()
            Button("Delete", role: .destructive) { deleteTarget = .project(project) }
        }
    }

    private func sourceRow(_ source: Source) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(source.type.badge)
                .font(.caption2)
                .foregroundStyle(color(for: source.type))
            Text(source.name)
        }
        .tag(source.id)
        .contextMenu {
            Button("Rename") { startRename(.source(source)) }
            Button("Edit Configuration...") { store.editSource = source }
            Divider()
            Button("Delete", role: .destructive) { deleteTarget = .source(source) }
        }
    }

    private func color(for type: SourceType) -> Color {
        switch type {
        case .lambda: Color(red: 1.0, green: 0.6, blue: 0.0)
        case .gitlabCICD: Color(red: 0.988, green: 0.427, blue: 0.149)
        case .secretsManager: Color(red: 0.867, green: 0.204, blue: 0.298)
        }
    }

    private var footer: some View {
        VStack(spacing: 2) {
            Divider()
            footerButton("Settings", systemImage: "gearshape", view: .settings)
            footerButton("Logs", systemImage: "list.bullet.rectangle", view: .logs, badge: store.logs.errorCount)
        }
        .padding(.bottom, 6)
        .background(.bar)
    }

    private func footerButton(_ title: String, systemImage: String, view: AppStore.MainView, badge: Int = 0) -> some View {
        Button {
            store.view = store.view == view ? .sources : view
        } label: {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                if badge > 0 {
                    Text("\(badge)")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(.red, in: Capsule())
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(store.view == view ? AnyShapeStyle(.selection) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 6))
        .animation(.easeInOut(duration: 0.12), value: store.view)
        .padding(.horizontal, 6)
    }

    private func startRename(_ target: RenameTarget) {
        renameText = target.currentName
        renameTarget = target
    }

    private func commitRename(_ target: RenameTarget) {
        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        switch target {
        case .project(let p): store.renameProject(id: p.id, name: trimmed)
        case .source(let s): store.renameSource(id: s.id, name: trimmed)
        }
    }

    private func commitDelete(_ target: DeleteTarget) {
        switch target {
        case .project(let p): store.deleteProject(id: p.id)
        case .source(let s): store.deleteSource(id: s.id)
        }
    }
}
