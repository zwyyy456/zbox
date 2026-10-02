import SwiftUI

struct QuicklinksSettingsView: View {
    let environment: AppEnvironment
    @State private var query = ""
    @State private var editing: Quicklink?
    private var plugin: QuicklinksPlugin { environment.quicklinksPlugin }

    var body: some View {
        VStack(alignment: .leading) {
            Toggle("Enable Quicklinks", isOn: Binding(get: { plugin.isEnabled }, set: environment.setQuicklinksEnabled))
            TextField("Search Quicklinks", text: $query)
            List {
                ForEach(plugin.store.items.filter { query.isEmpty || $0.name.localizedStandardContains(query) || $0.keywords.localizedStandardContains(query) }) { item in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(item.name)
                            Text(item.target).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Button("Edit") { editing = item }
                        Button("Delete", role: .destructive) { environment.deleteQuicklink(item) }
                    }
                }
            }
            Button("Add Quicklink") { editing = Quicklink() }
            if let error = plugin.store.loadError ?? plugin.statusMessage { SettingsErrorView(message: error) }
        }
        .padding(20)
        .sheet(item: $editing) { item in
            QuicklinkEditor(item: item) { environment.saveQuicklink($0) }
        }
    }
}

private struct QuicklinkEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var item: Quicklink
    let save: (Quicklink) -> Bool
    @State private var error: String?

    var body: some View {
        Form {
            TextField("Name", text: $item.name)
            Picker("Type", selection: $item.kind) {
                Text("URL").tag(Quicklink.Kind.url)
                Text("File or Folder").tag(Quicklink.Kind.file)
            }
            TextField("Target", text: $item.target)
            if item.kind == .file {
                Button("Choose File or Folder") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = true
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url { item.target = url.path }
                }
            }
            TextField("Keywords (separated by spaces)", text: $item.keywords)
            if let error { SettingsErrorView(message: error) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    do {
                        _ = try item.destination()
                        if save(item) { dismiss() }
                        else { error = String(localized: "The changes could not be saved. Check the storage location and try again.") }
                    } catch { self.error = error.localizedDescription }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24).frame(width: 540)
    }
}
