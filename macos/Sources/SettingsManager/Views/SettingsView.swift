import SwiftUI

struct SettingsView: View {
    @AppStorage("theme") private var theme = "system"

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
        }
        .formStyle(.grouped)
        .frame(maxWidth: 560, alignment: .leading)
        .navigationTitle("Settings")
    }
}
