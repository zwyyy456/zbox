import SwiftUI

struct ScriptCommandsSettingsView: View {
    let environment: AppEnvironment
    @State private var editing: ScriptCommand?
    private var plugin: ScriptCommandsPlugin { environment.scriptCommandsPlugin }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Enable Script Commands", isOn: Binding(get: { plugin.isEnabled }, set: environment.setScriptCommandsEnabled))
            Text("Scripts run as your user and can access your files and network. Only add scripts you trust.")
                .font(.caption).foregroundStyle(.secondary)
            List(plugin.store.items) { item in
                HStack {
                    VStack(alignment: .leading) {
                        Text(item.name)
                        Text(item.path).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    if !item.enabled { Text("Disabled").foregroundStyle(.secondary) }
                    Button("Edit") { editing = item }
                    Button("Delete", role: .destructive) { environment.deleteScriptCommand(item) }
                }
            }
            Button("Add Script") { editing = ScriptCommand() }
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

    var body: some View {
        VStack {
            Form {
                TextField("Name", text: $item.name)
                TextField("Keywords", text: $item.keywords)
                Toggle("Enabled", isOn: $item.enabled)
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
    }

    private func choose(directory: Bool, picked: (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = directory
        panel.canChooseFiles = !directory
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { picked(url.path) }
    }
}
