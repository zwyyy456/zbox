import SwiftUI

struct WorkspaceSettingsView: View {
    let environment: AppEnvironment
    @State private var editing: WorkspaceLayout?

    var body: some View {
        let plugin = environment.workspacePlugin
        Form {
            Section {
                Toggle("Enable Workspace", isOn: Binding(get: { plugin.isEnabled },
                    set: environment.setWorkspaceEnabled))
                Text("Save application window layouts and restore them locally using Accessibility permission.")
                    .font(.caption).foregroundStyle(.secondary)
                if !environment.isAccessibilityTrusted {
                    Button("Request Accessibility Permission", action: environment.requestAccessibilityPermission)
                    Button("Open Accessibility Settings", action: environment.openAccessibilitySettings)
                }
                if let message = plugin.statusMessage ?? plugin.store.errorMessage {
                    SettingsErrorView(message: message)
                }
            }
            Section("Workspaces") {
                if plugin.store.layouts.isEmpty {
                    Text("No saved workspaces.").foregroundStyle(.secondary)
                }
                ForEach(plugin.store.layouts) { layout in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(layout.name).lineLimit(1).help(layout.name)
                            Text(layout.entries.map(\.applicationName).joined(separator: ", "))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Button("Edit") { editing = layout }
                        Button("Delete", role: .destructive) { environment.deleteWorkspace(layout) }
                    }
                }
            }
        }
        .settingsPane()
        .sheet(item: $editing) { layout in
            WorkspaceEditor(layout: layout) { updated in
                environment.saveWorkspace(updated)
            }
        }
    }
}

private struct WorkspaceEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var layout: WorkspaceLayout
    let save: (WorkspaceLayout) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Workspace").font(.headline)
            TextField("Name", text: $layout.name)
            Text("Each application restores its current main window, not a specific document.")
                .font(.caption).foregroundStyle(.secondary)
            List {
                ForEach(layout.entries) { entry in
                    HStack {
                        Text(entry.applicationName)
                        Spacer()
                        Button("Remove") {
                            layout.entries.removeAll { $0.id == entry.id }
                            if layout.foregroundBundleID == entry.id { layout.foregroundBundleID = nil }
                        }
                    }
                }
            }
            Picker("Activate after restoring", selection: $layout.foregroundBundleID) {
                Text("Do not activate").tag(String?.none)
                ForEach(layout.entries) { entry in
                    Text(entry.applicationName).tag(Optional(entry.bundleID))
                }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save") {
                    layout.name = layout.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    save(layout)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(layout.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || layout.entries.isEmpty)
            }
        }
        .padding(20).frame(width: 520, height: 400)
    }
}
