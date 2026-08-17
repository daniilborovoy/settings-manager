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
                // NSApp.appearance instead of .preferredColorScheme: the latter
                // only themes SwiftUI content, leaving the window chrome and
                // background in the system appearance.
                .onChange(of: theme, initial: true) { _, newTheme in
                    switch newTheme {
                    case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
                    case "light": NSApp.appearance = NSAppearance(named: .aqua)
                    default: NSApp.appearance = nil
                    }
                }
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
            Group {
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
            .animation(.easeInOut(duration: 0.15), value: store.view)
            .animation(.easeInOut(duration: 0.15), value: store.selectedSourceID)
        }
        .onChange(of: store.selectedSourceID) { _, _ in
            store.sourceSelectionChanged()
        }
        .sheet(isPresented: $store.showAddProject) { AddProjectSheet() }
        .sheet(item: $store.addSourceProject) { AddSourceSheet(project: $0) }
        .sheet(item: $store.editSource) { EditSourceSheet(source: $0) }
        .sheet(item: $store.tokenPrompt) { UpdateTokenSheet(prompt: $0) }
    }
}
