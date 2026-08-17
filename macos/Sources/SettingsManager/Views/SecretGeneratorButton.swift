import SwiftUI
import AppKit

/// "Generate" button with a popover — port of SecretGenerator.tsx.
struct SecretGeneratorButton: View {
    let onUse: (String) -> Void
    @State private var open = false

    var body: some View {
        Button("Generate") { open.toggle() }
            .help("Generate a secure API key or password")
            .popover(isPresented: $open, arrowEdge: .bottom) {
                GeneratorPopover { value in
                    onUse(value)
                    open = false
                }
            }
    }
}

private struct GeneratorPopover: View {
    let onUse: (String) -> Void

    @State private var presetIndex = 0
    @State private var length = SecretGen.presets[0].length
    @State private var symbols = SecretGen.presets[0].symbols
    @State private var secret = ""
    @State private var copied = false

    private var preset: SecretGen.Preset { SecretGen.presets[presetIndex] }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: $presetIndex) {
                ForEach(SecretGen.presets.indices, id: \.self) { index in
                    Text(SecretGen.presets[index].label).tag(index)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: presetIndex) { _, index in
                let next = SecretGen.presets[index]
                length = next.length
                symbols = next.symbols
                regenerate()
            }

            HStack(spacing: 6) {
                Text(secret)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                Button {
                    regenerate()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Regenerate")
            }

            HStack(spacing: 12) {
                Stepper(value: Binding(
                    get: { length },
                    set: { length = min(SecretGen.maxLength, max(SecretGen.minLength, $0)); regenerate() }
                ), in: SecretGen.minLength...SecretGen.maxLength) {
                    Text("Length: \(length)")
                }
                if preset.hasSymbols {
                    Toggle("Symbols", isOn: Binding(
                        get: { symbols },
                        set: { symbols = $0; regenerate() }
                    ))
                }
            }
            .font(.callout)

            HStack {
                Button(copied ? "Copied" : "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(secret, forType: .string)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                }
                Spacer()
                Button("Use value") { onUse(secret) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .frame(width: 340)
        .onAppear(perform: regenerate)
    }

    private func regenerate() {
        secret = SecretGen.generate(kind: preset.kind, length: length, symbols: symbols)
        copied = false
    }
}
