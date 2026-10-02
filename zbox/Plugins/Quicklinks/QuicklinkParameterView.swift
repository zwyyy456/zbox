import SwiftUI

struct QuicklinkParameterView: View {
    @Bindable var plugin: QuicklinksPlugin
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(plugin.parameterItem?.name ?? "").font(.headline)
            Text((try? plugin.parameterItem?.destination().host) ?? "").foregroundStyle(.secondary)
            TextField(plugin.parameterItem?.parameterPrompt?.isEmpty == false
                ? plugin.parameterItem!.parameterPrompt! : String(localized: "Search value"), text: $plugin.query)
                .focused($focused)
                .onSubmit { plugin.openParameterizedLink() }
            if let error = plugin.parameterError { SettingsErrorView(message: error) }
            HStack {
                Button("Cancel") { plugin.stop() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Open") { plugin.openParameterizedLink() }
                    .disabled(plugin.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .onAppear { focused = true }
        .onChange(of: plugin.parameterItem?.id) { focused = true }
    }
}

@MainActor final class QuicklinkParameterPanel: NSPanel {
    var onDismiss: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func close() { onDismiss?(); super.close() }
    override func cancelOperation(_ sender: Any?) { onDismiss?() }
}
