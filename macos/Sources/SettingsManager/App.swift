import SwiftUI
import AppKit

@main
struct SettingsManagerApp: App {
    @State private var store = AppStore()
    @AppStorage("theme") private var theme = "system"

    init() {
        // SPM executables aren't app bundles; make sure a window comes forward
        // when launched via `swift run`.
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    var body: some Scene {
        WindowGroup("Settings Manager") {
            ContentView()
                .environment(store)
                .preferredColorScheme(theme == "dark" ? .dark : theme == "light" ? .light : nil)
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1200, height: 800)
    }
}

struct ContentView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 400)
        } detail: {
            switch store.view {
            case .logs:
                LogsView()
            case .settings:
                SettingsView()
            case .sources:
                if store.selectedSource != nil {
                    VariableEditorView()
                } else {
                    ContentUnavailableView(
                        "No source selected",
                        systemImage: "sidebar.left",
                        description: Text("Select a source to view and edit its variables")
                    )
                }
            }
        }
        .onChange(of: store.selectedSourceID) { _, _ in
            store.sourceSelectionChanged()
        }
        .sheet(isPresented: $store.showAddProject) { AddProjectSheet() }
        .sheet(item: $store.addSourceProject) { AddSourceSheet(project: $0) }
        .sheet(item: $store.tokenPrompt) { UpdateTokenSheet(prompt: $0) }
    }
}
