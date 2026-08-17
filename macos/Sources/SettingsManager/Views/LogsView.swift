import SwiftUI

struct LogsView: View {
    @Environment(AppStore.self) private var store
    @State private var expandedID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Logs").font(.title2.bold())
                Spacer()
                Text("\(store.logs.entries.count) call\(store.logs.entries.count == 1 ? "" : "s")")
                    .foregroundStyle(.secondary)
                Button("Clear") {
                    store.logs.clear()
                    expandedID = nil
                }
            }
            .padding(16)

            if store.logs.entries.isEmpty {
                ContentUnavailableView(
                    "No calls yet",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Interact with the app to see logs here.")
                )
            } else {
                List(store.logs.entries) { entry in
                    logRow(entry)
                }
                .listStyle(.inset)
            }
        }
    }

    @ViewBuilder
    private func logRow(_ entry: LogStore.Entry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(entry.ok ? "OK" : "ERR")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(entry.ok ? .green : .red, in: Capsule())
                Text(entry.command)
                    .font(.system(.body, design: .monospaced))
                Spacer()
                Text("\(entry.durationMS)ms")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(entry.time.formatted(date: .omitted, time: .standard))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Image(systemName: expandedID == entry.id ? "chevron.up" : "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                expandedID = expandedID == entry.id ? nil : entry.id
            }

            if expandedID == entry.id {
                if let args = entry.args, !args.isEmpty {
                    detailBlock("Arguments", args)
                }
                if let error = entry.error {
                    detailBlock("Error", error, isError: true)
                } else if let result = entry.result {
                    detailBlock("Result", result)
                } else {
                    Text("No result").font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func detailBlock(_ label: String, _ content: String, isError: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            ScrollView(.horizontal) {
                Text(content)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(isError ? .red : .primary)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 220)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
    }
}
