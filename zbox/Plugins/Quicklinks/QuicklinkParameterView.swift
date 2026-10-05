import SwiftUI

struct QuicklinkParameterView: View {
    @Bindable var plugin: QuicklinksPlugin
    @FocusState private var focused: Bool
    private var prompt: String {
        if let value = plugin.parameterItem?.parameterPrompt, !value.isEmpty { return value }
        return String(localized: "Search value")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if plugin.choosingTemplate {
                Picker("Quicklink", selection: Binding(get: { plugin.parameterItem?.id }, set: { id in
                    plugin.parameterItem = plugin.store.items.first { $0.id == id }
                    plugin.parameterError = nil
                })) {
                    ForEach(plugin.store.items.filter { $0.kind == .template }) { item in
                        Text(item.name).tag(Optional(item.id))
                    }
                }
            } else { Text(plugin.parameterItem?.name ?? "").font(.headline) }
            Text((try? plugin.parameterItem?.destination().host) ?? "").foregroundStyle(.secondary)
            TextField(prompt, text: $plugin.query)
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
