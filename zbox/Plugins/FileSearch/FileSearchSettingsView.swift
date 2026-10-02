import SwiftUI

struct FileSearchSettingsView: View {
    let environment: AppEnvironment
    private var plugin: FileSearchPlugin { environment.fileSearchPlugin }

    var body: some View {
        Form {
            Toggle("Enable File Search", isOn: Binding(get: { plugin.isEnabled }, set: environment.setFileSearchEnabled))
            Section("Search Folders") {
                ForEach(plugin.settings.roots) { root in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(root.url.path).textSelection(.enabled)
                        if let status = plugin.rootStatus[root.id] { Text(status).font(.caption).foregroundStyle(.secondary) }
                        Toggle("Include Hidden Files", isOn: Binding(get: { root.includesHidden }, set: {
                            var updated = root; updated.includesHidden = $0; plugin.save(updated)
                        }))
                        ForEach(root.exclusions, id: \.self) { path in
                            HStack {
                                Text(path).font(.caption)
                                Spacer()
                                Button("Remove Exclusion") {
                                    var updated = root; updated.exclusions.removeAll { $0 == path }; plugin.save(updated)
                                }
                            }
                        }
                        HStack {
                            Button("Rescan") { plugin.rescan(root) }.disabled(!plugin.isEnabled)
                            Button("Exclude Subfolder") { plugin.excludeFolder(from: root) }
                            Spacer()
                            Button("Remove Folder", role: .destructive) { plugin.remove(root) }
                        }
                    }
                }
                HStack {
                    Button("Add Folder", action: plugin.chooseFolder)
                    Menu("Add Common Folder") {
                        Button("Desktop") { plugin.add(URL.homeDirectory.appending(path: "Desktop")) }
                        Button("Documents") { plugin.add(URL.homeDirectory.appending(path: "Documents")) }
                        Button("Downloads") { plugin.add(URL.homeDirectory.appending(path: "Downloads")) }
                    }
                }
                Text("Only selected folders are indexed. File contents are not read.").font(.caption).foregroundStyle(.secondary)
            }
            if let error = plugin.settings.error ?? plugin.statusMessage { SettingsErrorView(message: error) }
        }.settingsPane()
    }
}
