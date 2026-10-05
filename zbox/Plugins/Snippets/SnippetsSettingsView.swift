import SwiftUI

struct SnippetsSettingsView: View {
    let environment: AppEnvironment
    @State private var query = ""
    @State private var deleting: Snippet?
    private var plugin: SnippetsPlugin { environment.snippetsPlugin }

    var body: some View {
        @Bindable var plugin = plugin
        VStack(alignment: .leading) {
            Toggle("Enable Snippets", isOn: Binding(get: { plugin.isEnabled }, set: environment.setSnippetsEnabled))
            TextField("Search Snippets", text: $query)
            List {
                ForEach(plugin.store.items.filter { query.isEmpty || [$0.name, $0.keywords, $0.body].contains { $0.localizedStandardContains(query) } }) { item in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(item.name)
                            if !item.group.isEmpty { Text(item.group).font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Button("Edit") { plugin.editingSnippet = item }
                        Button("Delete", role: .destructive) { deleting = item }
                    }
                }
            }
            Button("Add Snippet") { plugin.editingSnippet = Snippet() }
            if let error = plugin.store.loadError ?? plugin.statusMessage { SettingsErrorView(message: error) }
        }
        .padding(20)
        .sheet(item: $plugin.editingSnippet) { item in SnippetEditor(item: item) { environment.saveSnippet($0) } }
        .alert("Delete Snippet?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Cancel", role: .cancel) { deleting = nil }
            Button("Delete", role: .destructive) {
                if let deleting { environment.deleteSnippet(deleting) }
                deleting = nil
            }
        }
    }
}

private struct SnippetEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var item: Snippet
    let save: (Snippet) -> Bool
    @State private var error: String?
    @State private var selection: TextSelection?
    @FocusState private var bodyFocused: Bool

    private func insert(_ token: String) {
        let range: Range<String.Index>
        if let selection, case .selection(let selectedRange) = selection.indices { range = selectedRange }
        else { range = item.body.endIndex..<item.body.endIndex }
        let offset = item.body.distance(from: item.body.startIndex, to: range.lowerBound)
        item.body.replaceSubrange(range, with: token)
        let cursor = item.body.index(item.body.startIndex, offsetBy: offset + token.count)
        selection = TextSelection(insertionPoint: cursor)
        bodyFocused = true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Name", text: $item.name)
            TextField("Keywords (separated by spaces)", text: $item.keywords)
            TextField("Group (optional)", text: $item.group)
            HStack {
                Text("Snippet Text").font(.headline)
                Spacer()
                Menu("Insert Variable") {
                    Button("Date (yyyy-MM-dd)") { insert("{{date}}") }
                    Button("Time (HH:mm)") { insert("{{time}}") }
                    Button("Clipboard Text") { insert("{{clipboard}}") }
                }
            }
            TextEditor(text: $item.body, selection: $selection)
                .focused($bodyFocused)
                .font(.system(.body, design: .monospaced))
                .accessibilityLabel("Snippet Text")
                .border(.quaternary)
            Text("Variables expand only when copied or pasted. Prefix {{ with a backslash to keep it literal.").font(.caption).foregroundStyle(.secondary)
            if let error { SettingsErrorView(message: error) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    if save(item) { dismiss() }
                    else { error = String(localized: "The changes could not be saved. Check the storage location and try again.") }
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || item.body.isEmpty)
            }
        }.padding(24).frame(width: 580, height: 460)
    }
}
