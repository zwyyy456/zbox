import SwiftUI

struct ExtensionSettingsView: View {
    @Bindable var manager: ExtensionManager
    @State private var removing: ExtensionInstallation?
    @State private var deleteData = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Extensions run as your user and can access files and the network. Install only code you trust.")
                .font(.caption).foregroundStyle(.secondary)
            List(manager.items) { item in
                HStack {
                    Toggle(isOn: Binding(get: { item.enabled }, set: { enabled in Task { await manager.setEnabled(item, enabled) } })) {
                        VStack(alignment: .leading) {
                            Text(item.manifest.name)
                            Text("\(item.id) · \(item.manifest.version)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("Uninstall") { deleteData = false; removing = item }
                }
            }
            HStack {
                Button("Import Package…", action: choosePackage)
                if manager.busy { ProgressView().controlSize(.small) }
            }
            if let error = manager.error { SettingsErrorView(message: error) }
        }
        .padding(20).disabled(manager.busy || manager.loadFailed)
        .sheet(item: Binding(get: { manager.candidate }, set: { _ in })) { item in
            VStack(alignment: .leading, spacing: 12) {
                Text(item.manifest.name).font(.title2)
                Text("\(item.id) · \(item.manifest.version)")
                Text(item.source).font(.caption).textSelection(.enabled)
                Text(item.manifest.commands.map(\.name).joined(separator: ", "))
                Text("Requested host capabilities: \(item.grants.joined(separator: ", "))")
                Text("Installing trusts this code. Replacing an installed extension stops its current session and preserves settings.")
                if let error = manager.error { SettingsErrorView(message: error) }
                HStack {
                    Button("Cancel") { Task { await manager.discardCandidate() } }
                    Spacer()
                    Button("Trust and Install") { Task { await manager.install() } }.keyboardShortcut(.defaultAction)
                }.disabled(manager.busy)
            }.padding(24).frame(width: 520).interactiveDismissDisabled()
        }
        .sheet(item: $removing) { item in
            VStack(alignment: .leading, spacing: 16) {
                Text("Uninstall \(item.manifest.name)?").font(.headline)
                Text("This stops the current session and removes its commands and shortcuts.")
                Toggle("Delete extension data and credentials", isOn: $deleteData)
                HStack {
                    Button("Cancel") { removing = nil }
                    Spacer()
                    Button("Uninstall", role: .destructive) {
                        Task { await manager.uninstall(item, deleteData: deleteData); removing = nil }
                    }
                }
            }.padding(24).frame(width: 480)
        }
    }

    private func choosePackage() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { Task { await manager.prepare(url) } }
    }
}
