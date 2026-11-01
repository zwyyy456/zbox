import SwiftUI

struct ClipboardHistoryView: View {
    @Bindable var plugin: ClipboardHistoryPlugin
    @FocusState private var searchFocused: Bool

    var body: some View {
        let hasSelection = plugin.selectedID != nil
        VStack(spacing: 0) {
            ToolSearchBar {
                TextField("Search Clipboard History", text: $plugin.query)
                    .focused($searchFocused)
                    .onSubmit { plugin.pasteSelection() }
            } accessory: {
                Picker("Filter", selection: $plugin.filter) {
                    ForEach(ClipboardHistoryFilter.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    List(selection: $plugin.selectedID) {
                        ForEach(plugin.filteredEntries) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: ["png", "tiff"].contains(entry.kind) ? "photo" : "doc.text")
                                    Text(entry.text).lineLimit(2)
                                    if entry.pinned { Image(systemName: "pin.fill").accessibilityLabel("Pinned") }
                                }
                                Text(entry.copiedAt, style: .relative).font(.caption).foregroundStyle(.secondary)
                            }
                            .tag(entry.id)
                            .contextMenu {
                                Button("Paste") { plugin.selectedID = entry.id; plugin.pasteSelection() }
                                Button("Copy") { plugin.selectedID = entry.id; plugin.copySelection() }
                                Button(entry.pinned ? String(localized: "Unpin") : String(localized: "Pin")) {
                                    plugin.selectedID = entry.id
                                    plugin.togglePin()
                                }
                                Divider()
                                Button("Delete", role: .destructive) { plugin.selectedID = entry.id; plugin.deleteSelection() }
                            }
                        }
                    }
                    if geometry.size.width >= 640 {
                        Divider()
                        ScrollView {
                            if let entry = plugin.entries.first(where: { $0.id == plugin.selectedID }) {
                                if ["png", "tiff"].contains(entry.kind) {
                                    if let image = plugin.previewImage {
                                        Image(nsImage: image).resizable().scaledToFit().padding()
                                            .accessibilityLabel(entry.text)
                                    } else { Text("Image preview unavailable").foregroundStyle(.secondary).padding() }
                                } else {
                                    Text(entry.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding()
                                }
                            }
                        }.frame(width: geometry.size.width * 0.45)
                    }
                }
                .overlay {
                    if plugin.filteredEntries.isEmpty {
                        ContentUnavailableView("No Clipboard Items", systemImage: "clipboard",
                            description: Text("Copy something after enabling Clipboard History, or change your search and filter."))
                    }
                }
            }
            ToolActionBar(primaryTitle: String(localized: "Paste"), isPrimaryEnabled: hasSelection,
                          primary: plugin.pasteSelection) {
                if let message = plugin.statusMessage {
                    Text(message)
                } else {
                    Text("⌘↩ Copy · Right-click for more · Esc Close")
                }
            } secondary: {
                Menu("More") {
                    Button(plugin.entries.first(where: { $0.id == plugin.selectedID })?.pinned == true
                           ? String(localized: "Unpin") : String(localized: "Pin"), action: plugin.togglePin)
                    Divider()
                    Button("Delete", role: .destructive, action: plugin.deleteSelection)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(!hasSelection)
                Button("Copy", action: plugin.copySelection).disabled(!hasSelection)
            }
        }
        .onAppear { searchFocused = true }
        .onChange(of: plugin.filter) { plugin.selectedID = plugin.filteredEntries.first?.id }
        .onChange(of: plugin.query) { plugin.selectedID = plugin.filteredEntries.first?.id }
        .onExitCommand(perform: plugin.dismiss)
    }
}

struct ClipboardHistorySettingsView: View {
    @Bindable var plugin: ClipboardHistoryPlugin
    let onEnabledChanged: @MainActor @Sendable (Bool) -> Void
    let shortcutError: String?
    @State private var confirmsClear = false

    var body: some View {
        Form {
            Toggle("Enable Clipboard History", isOn: Binding(get: { plugin.isEnabled }, set: onEnabledChanged))
            Text("Stores future copies on this Mac. History is not encrypted or synced. Sensitive markers and excluded apps are skipped, but not all secrets can be detected.")
                .foregroundStyle(.secondary)
            if let message = plugin.statusMessage { Text(message).foregroundStyle(.secondary) }
            if let shortcutError { SettingsErrorView(message: shortcutError) }
            Button("Allow Clipboard Access / Resume", action: plugin.requestClipboardAccess)
                .disabled(!plugin.isEnabled || plugin.isRecording)
            Picker("Keep History", selection: $plugin.retentionDays) {
                Text("1 Day").tag(1)
                Text("7 Days").tag(7)
                Text("30 Days").tag(30)
            }
            Text("Up to 500 items and 100 MiB. Pinned items do not expire but count toward the limit.")
                .font(.caption).foregroundStyle(.secondary)
            Section("Excluded Applications") {
                ForEach(plugin.excludedApplications.sorted(), id: \.self) { id in
                    HStack {
                        Text(id).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Remove") { plugin.removeExcludedApplication(id) }
                    }
                }
                Button("Add Application…", action: plugin.chooseExcludedApplication)
            }
            Section("Direct Paste") {
                AccessibilityPermissionRow(isTrusted: plugin.isPasteTrusted,
                                           request: plugin.requestPastePermission,
                                           openSettings: plugin.openAccessibilitySettings)
            }
            Button("Clear Clipboard History…", role: .destructive) { confirmsClear = true }
        }
        .settingsPane()
        .confirmationDialog("Delete all clipboard history, including pinned items?", isPresented: $confirmsClear) {
            Button("Delete All", role: .destructive, action: plugin.clearHistory)
        }
    }
}
