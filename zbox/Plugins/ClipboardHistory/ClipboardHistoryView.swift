import SwiftUI

struct ClipboardHistoryView: View {
    @Bindable var plugin: ClipboardHistoryPlugin
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search Clipboard History", text: $plugin.query)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .padding()
                .onSubmit { plugin.copySelection() }
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    List(selection: $plugin.selectedID) {
                        ForEach(plugin.filteredEntries) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.text).lineLimit(2)
                                Text(entry.copiedAt, style: .relative).font(.caption).foregroundStyle(.secondary)
                            }
                            .tag(entry.id)
                        }
                    }
                    if geometry.size.width >= 640 {
                        Divider()
                        ScrollView {
                            if let entry = plugin.entries.first(where: { $0.id == plugin.selectedID }) {
                                Text(entry.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding()
                            }
                        }.frame(width: geometry.size.width * 0.45)
                    }
                }
            }
            if let message = plugin.statusMessage {
                Text(message).font(.caption).foregroundStyle(.secondary).padding(.horizontal)
            }
            HStack {
                Button("Copy", action: plugin.copySelection).keyboardShortcut(.return, modifiers: .command)
                Spacer()
                Button("Delete", action: plugin.deleteSelection)
            }.disabled(plugin.selectedID == nil).padding()
        }
        .onAppear { searchFocused = true }
        .onChange(of: plugin.query) { plugin.selectedID = plugin.filteredEntries.first?.id }
        .onExitCommand(perform: plugin.dismiss)
    }
}

struct ClipboardHistorySettingsView: View {
    @Bindable var plugin: ClipboardHistoryPlugin
    @State private var confirmsClear = false

    var body: some View {
        Form {
            Toggle("Enable Clipboard History", isOn: Binding(get: { plugin.isEnabled }, set: plugin.setEnabled))
            Text("Stores future copies on this Mac. History is not encrypted or synced. Sensitive markers and excluded apps are skipped, but not all secrets can be detected.")
                .foregroundStyle(.secondary)
            if let message = plugin.statusMessage { Text(message).foregroundStyle(.secondary) }
            Button("Allow Clipboard Access / Resume", action: plugin.requestClipboardAccess)
                .disabled(!plugin.isEnabled || plugin.isRecording)
            Button("Clear Clipboard History…", role: .destructive) { confirmsClear = true }
        }
        .settingsPane()
        .confirmationDialog("Delete all clipboard history, including pinned items?", isPresented: $confirmsClear) {
            Button("Delete All", role: .destructive, action: plugin.clearHistory)
        }
    }
}
