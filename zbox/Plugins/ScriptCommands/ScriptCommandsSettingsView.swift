import SwiftUI

struct ScriptCommandsSettingsView: View {
    let environment: AppEnvironment
    @State private var editing: ScriptCommand?
    private var plugin: ScriptCommandsPlugin { environment.scriptCommandsPlugin }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Enable Automation", isOn: Binding(get: { plugin.isEnabled }, set: environment.setScriptCommandsEnabled))
            Text("Scripts run as your user. Apple Shortcuts handles its own permissions and prompts. Add only automation you trust.")
                .font(.caption).foregroundStyle(.secondary)
            List(plugin.store.items) { item in
                HStack {
                    VStack(alignment: .leading) {
                        Text(item.name)
                        Text(item.shortcut?.name ?? item.path).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    if !item.enabled { Text("Disabled").foregroundStyle(.secondary) }
                    Button("Edit") { editing = item }
                    Button("Delete", role: .destructive) { environment.deleteScriptCommand(item) }
                }
            }
            HStack {
                Button("Add Script") { editing = ScriptCommand() }
                Button("Add Apple Shortcut") {
                    var item = ScriptCommand()
                    item.shortcut = AppleShortcutConfiguration(identifier: UUID(), name: "")
                    editing = item
                }
            }
            if let error = plugin.store.loadError ?? plugin.statusMessage { SettingsErrorView(message: error) }
        }.padding(20)
            .sheet(item: $editing) { ScriptCommandEditor(item: $0, save: environment.saveScriptCommand) }
    }
}

private struct ScriptCommandEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var item: ScriptCommand
    let save: (ScriptCommand) -> Bool
    @State private var error: String?
    @State private var shortcuts: [AppleShortcutEntry] = []
    @State private var isLoading = false
    @State private var refreshID = UUID()

    var body: some View {
        VStack {
            Form {
                TextField("Name", text: $item.name)
                TextField("Keywords", text: $item.keywords)
                Toggle("Enabled", isOn: $item.enabled)
                if item.shortcut != nil {
                    Picker("Apple Shortcut", selection: Binding(get: { item.shortcut?.identifier }, set: { id in
                        if let entry = shortcuts.first(where: { $0.id == id }) {
                            item.shortcut?.identifier = entry.id
                            item.shortcut?.name = entry.name
                            if item.name.isEmpty { item.name = entry.name }
                        }
                    })) {
                        if let current = item.shortcut, !shortcuts.contains(where: { $0.id == current.identifier }) {
                            Text(current.name.isEmpty ? String(localized: "Choose a Shortcut") : current.name).tag(Optional(current.identifier))
                        }
                        ForEach(shortcuts) { entry in
                            Text(shortcuts.filter { $0.name == entry.name }.count > 1
                                 ? "\(entry.name) · \(entry.id.uuidString.prefix(8))" : entry.name).tag(Optional(entry.id))
                        }
                    }
                    Button("Refresh Shortcuts") { refreshID = UUID() }.disabled(isLoading)
                    if isLoading { ProgressView().controlSize(.small) }
                    Toggle("Ask for Text Input", isOn: Binding(get: { item.shortcut?.acceptsText ?? false }, set: { item.shortcut?.acceptsText = $0 }))
                    TextField("Timeout (seconds)", value: $item.timeout, format: .number)
                    Text("Text input uses a private temporary file that is removed after execution. Shortcut actions may save or send the input.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                LabeledContent("Script File") {
                    Text(item.path).lineLimit(2).textSelection(.enabled)
                    Button("Choose…") { choose(directory: false) { item.path = $0 } }
                }
                TextField("Interpreter (empty = direct execution)", text: $item.interpreter)
                HStack {
                    Button("zsh") { item.interpreter = "/bin/zsh" }
                    Button("bash") { item.interpreter = "/bin/bash" }
                    Button("AppleScript") { item.interpreter = "/usr/bin/osascript" }
                    Button("Choose Interpreter…") { choose(directory: false) { item.interpreter = $0 } }
                }
                TextField("Working Directory (empty = script folder)", text: $item.directory)
                Button("Choose Working Directory…") { choose(directory: true) { item.directory = $0 } }
                TextField("Timeout (seconds)", value: $item.timeout, format: .number)
                Text("Fixed Arguments (one argument per line)").font(.headline)
                PlainTextEditor(text: Binding(get: { item.arguments.joined(separator: "\n") }, set: {
                    item.arguments = $0.isEmpty ? [] : $0.components(separatedBy: "\n")
                }), label: String(localized: "Fixed Arguments (one argument per line)")).frame(height: 70)
                Text("Runtime Parameters (appended in this order)").font(.headline)
                ForEach($item.parameters) { $parameter in
                    HStack {
                        TextField("Parameter Name", text: $parameter.name)
                        TextField("Default Value", text: $parameter.defaultValue)
                        Toggle("Required", isOn: $parameter.required)
                        Button("Remove") { item.parameters.removeAll { $0.id == parameter.id } }
                    }
                }
                Button("Add Parameter") { item.parameters.append(ScriptParameter()) }
                }
            }.formStyle(.grouped)
            if let error { Text(error).foregroundStyle(.red).padding(.horizontal) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    do {
                        try item.validate()
                        if save(item) { dismiss() }
                        else { error = String(localized: "The changes could not be saved. Check the storage location and try again.") }
                    } catch { self.error = error.localizedDescription }
                }.keyboardShortcut(.defaultAction)
            }.padding()
        }.frame(width: 650, height: 620)
        .task(id: refreshID) {
            guard item.shortcut != nil else { return }
            isLoading = true
            do {
                let entries = try await AppleShortcuts.list()
                try Task.checkCancellation()
                shortcuts = entries
                error = nil
                isLoading = false
            } catch is CancellationError { }
            catch { if !Task.isCancelled { self.error = error.localizedDescription; isLoading = false } }
        }
    }

    private func choose(directory: Bool, picked: (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = directory
        panel.canChooseFiles = !directory
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { picked(url.path) }
    }
}
