import SwiftUI

struct SnippetsView: View {
    @Bindable var plugin: SnippetsPlugin
    @FocusState private var searchFocused: Bool
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                TextField("Search Snippets", text: $plugin.query).focused($searchFocused)
                Picker("Group", selection: $plugin.group) {
                    Text("All Groups").tag("")
                    ForEach(plugin.groups, id: \.self) { Text($0).tag($0) }
                }.frame(maxWidth: 180)
            }
            HSplitView {
                List(plugin.filteredItems, selection: $plugin.selectedID) { item in
                    VStack(alignment: .leading) {
                        Text(item.name)
                        if !item.group.isEmpty { Text(item.group).font(.caption).foregroundStyle(.secondary) }
                    }.tag(item.id)
                }.frame(minWidth: 180, idealWidth: 240)
                ScrollView {
                    Text(plugin.selectedItem?.body ?? String(localized: "No snippets found."))
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading).padding(12)
                }.frame(minWidth: 260)
            }
            if let error = plugin.store.loadError ?? plugin.statusMessage {
                SettingsErrorView(message: error)
            }
            if plugin.needsPastePermission {
                HStack {
                    Button("Request Accessibility for Direct Paste", action: plugin.requestPastePermission)
                    Button("Open Accessibility Settings", action: plugin.openAccessibilitySettings)
                }
            }
            HStack {
                Text("Return to paste • ⌘Return to copy • Esc to close").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Copy") { plugin.copySelection() }.disabled(plugin.selectedItem == nil)
                Button("Paste") { plugin.pasteSelection() }.disabled(plugin.selectedItem == nil)
            }
        }
        .padding(16)
        .onAppear { searchFocused = true }
        .onChange(of: plugin.query) { plugin.selectedID = plugin.filteredItems.first?.id }
        .onChange(of: plugin.group) { plugin.selectedID = plugin.filteredItems.first?.id }
    }
}
