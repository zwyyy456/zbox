import SwiftUI

struct SnippetsView: View {
    @Bindable var plugin: SnippetsPlugin
    @State private var searchFocused = false
    var body: some View {
        let hasSelection = plugin.selectedItem != nil
        VStack(spacing: 0) {
            ToolSearchBar {
                NativeSearchField(title: String(localized: "Search Snippets"), text: $plugin.query,
                                  isFocused: $searchFocused)
            } accessory: {
                Picker("Group", selection: $plugin.group) {
                    Text("All Groups").tag("")
                    ForEach(plugin.groups, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
            HSplitView {
                List(plugin.filteredItems, selection: $plugin.selectedID) { item in
                    VStack(alignment: .leading) {
                        Text(item.name)
                        if !item.group.isEmpty { Text(item.group).font(.caption).foregroundStyle(.secondary) }
                    }.tag(item.id)
                }
                .frame(minWidth: 180, idealWidth: 240)
                .overlay {
                    if plugin.filteredItems.isEmpty {
                        ContentUnavailableView("No Snippets Found", systemImage: "text.quote",
                                               description: Text("Change your search or group."))
                    }
                }
                ScrollView {
                    Text(plugin.selectedItem?.body ?? "")
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading).padding(12)
                }.frame(minWidth: 260)
            }
            if plugin.needsPastePermission {
                HStack {
                    Button("Request Accessibility for Direct Paste", action: plugin.requestPastePermission)
                    Button("Open Accessibility Settings", action: plugin.openAccessibilitySettings)
                }.padding(.top, 8)
            }
            ToolActionBar(primaryTitle: String(localized: "Paste"), isPrimaryEnabled: hasSelection,
                          primary: plugin.pasteSelection) {
                if let error = plugin.store.loadError ?? plugin.statusMessage {
                    SettingsErrorView(message: error)
                } else {
                    Text("⌘↩ Copy · Esc Close")
                }
            } secondary: {
                Button("Copy") { plugin.copySelection() }.disabled(!hasSelection)
            }
        }
        .onAppear { searchFocused = true }
        .onChange(of: plugin.query) { plugin.selectedID = plugin.filteredItems.first?.id }
        .onChange(of: plugin.group) { plugin.selectedID = plugin.filteredItems.first?.id }
    }
}
