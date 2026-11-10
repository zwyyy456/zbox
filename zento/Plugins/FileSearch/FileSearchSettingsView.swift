import SwiftUI

struct FileSearchSettingsView: View {
    let environment: AppEnvironment
    @State private var editingRoot: FileSearchRoot?
    @State private var clearing = false
    @State private var showingAccessSetup = false
    @State private var chooseFoldersAfterSetup = false
    private var plugin: FileSearchPlugin { environment.fileSearchPlugin }

    var body: some View {
        Form {
            Toggle("Enable File Search", isOn: Binding(get: { plugin.isEnabled }, set: { enabled in
                if enabled { showingAccessSetup = true }
                else { environment.setFileSearchEnabled(false) }
            }))
            Section("Full Disk Access") {
                Text("Allow Full Disk Access in System Settings to search protected folders. If access is denied, choose folders you can access below.")
                    .foregroundStyle(.secondary)
                Button("Grant Access...", action: plugin.openFullDiskAccessSettings)
                Button("Rescan Search Folders") {
                    for root in plugin.settings.roots { plugin.rescan(root) }
                }.disabled(!plugin.isEnabled)
            }
            Section("Search Folders") {
                ForEach(plugin.settings.roots) { root in
                    HStack {
                        Label(root.url.lastPathComponent, systemImage: "folder")
                            .lineLimit(1).truncationMode(.middle)
                            .help(root.url.path)
                        if plugin.settings.roots.filter({ $0.url.lastPathComponent == root.url.lastPathComponent }).count > 1 {
                            Text(root.url.deletingLastPathComponent().path)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        if let status = plugin.rootStatus[root.id] {
                            Text(status.title).font(.caption).foregroundStyle(.secondary)
                                .lineLimit(2).help(status.title)
                        }
                        Menu {
                            Button("Rescan") { plugin.rescan(root) }.disabled(!plugin.isEnabled)
                            Button("Folder Settings...") { editingRoot = root }
                            Divider()
                            Button("Remove Folder", role: .destructive) { plugin.remove(root) }
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .menuStyle(.borderlessButton).fixedSize()
                        .accessibilityLabel("Folder Actions")
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
            Button("Clear File Index", role: .destructive) { clearing = true }.disabled(plugin.isClearing)
            if let error = plugin.settings.error ?? plugin.statusMessage { SettingsErrorView(message: error) }
        }.settingsPane()
        .disabled(plugin.isClearing)
        .sheet(item: $editingRoot) { root in
            FileSearchFolderSettingsView(plugin: plugin, rootID: root.id)
        }
        .sheet(isPresented: $showingAccessSetup, onDismiss: {
            if chooseFoldersAfterSetup {
                chooseFoldersAfterSetup = false
                plugin.chooseFolder()
            }
        }) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Set Up File Search").font(.title2.bold())
                Text("Enable Full Disk Access for Zento in System Settings, then return here and start searching. macOS may ask you to restart Zento.")
                Text("By default, search your home folder, excluding Library and hidden files. Existing search folders are kept. File contents are not read.")
                    .foregroundStyle(.secondary)
                Button("Grant Access...", action: plugin.openFullDiskAccessSettings)
                Button("Start Searching") {
                    guard plugin.prepareDefaultSearchFolders() else { return }
                    showingAccessSetup = false
                    environment.setFileSearchEnabled(true)
                }.keyboardShortcut(.defaultAction)
                Button("Not Now — Choose Folders") {
                    showingAccessSetup = false
                    environment.setFileSearchEnabled(true)
                    chooseFoldersAfterSetup = true
                }
                if let message = plugin.settings.error ?? plugin.statusMessage { SettingsErrorView(message: message) }
                Button("Cancel") { showingAccessSetup = false }.keyboardShortcut(.cancelAction)
            }
            .padding(24)
            .frame(width: 460)
            .fixedSize(horizontal: false, vertical: true)
        }
        .alert("Clear File Index?", isPresented: $clearing) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) { plugin.clearIndex() }
        } message: { Text("Only the index is removed. Your files and search folders are kept. Enabled folders will be rebuilt.") }
    }
}

private struct FileSearchFolderSettingsView: View {
    let plugin: FileSearchPlugin
    let rootID: UUID
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Folder Settings...").font(.headline)
            if let root = plugin.settings.roots.first(where: { $0.id == rootID }) {
                Text(root.url.path).textSelection(.enabled)
                Toggle("Include Hidden Files", isOn: Binding(get: { root.includesHidden }, set: {
                    var updated = root; updated.includesHidden = $0; plugin.save(updated)
                }))
                Text("Excluded Folders").font(.headline)
                ScrollView {
                    VStack(alignment: .leading) {
                        ForEach(root.exclusions, id: \.self) { path in
                            HStack {
                                Text(path).lineLimit(2).truncationMode(.middle)
                                Spacer()
                                Button("Remove Exclusion") {
                                    var updated = root; updated.exclusions.removeAll { $0 == path }; plugin.save(updated)
                                }
                            }
                        }
                    }
                }.frame(maxHeight: 180)
                Button("Exclude Subfolder") { plugin.excludeFolder(from: root) }
            }
            if let error = plugin.statusMessage { SettingsErrorView(message: error) }
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 480)
    }
}
