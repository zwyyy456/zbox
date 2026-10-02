import SwiftUI

struct WorkspaceSettingsView: View {
    let environment: AppEnvironment
    @State private var editing: WorkspaceLayout?

    var body: some View {
        @Bindable var plugin = environment.workspacePlugin
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
                Button("Save Current Workspace") { capture() }
                    .disabled(!plugin.isEnabled)
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
                        Menu {
                            Button("Edit") { editing = layout }
                            Button("Update from Current Layout") { capture(replacing: layout) }
                                .disabled(!plugin.isEnabled)
                        } label: { Image(systemName: "ellipsis") }
                        .menuStyle(.borderlessButton).fixedSize()
                        .accessibilityLabel("Workspace Actions")
                        Button("Delete", role: .destructive) { environment.deleteWorkspace(layout) }
                    }
                }
            }
        }
        .settingsPane()
        .sheet(item: $plugin.capture) { snapshot in
            WorkspaceCaptureView(snapshot: snapshot) { layout in environment.saveWorkspace(layout) }
        }
        .sheet(item: $editing) { layout in
            WorkspaceEditor(layout: layout) { updated in
                environment.saveWorkspace(updated)
            }
        }
    }
    private func capture(replacing: WorkspaceLayout? = nil) {
        do { try environment.workspacePlugin.prepareCapture(replacing: replacing) }
        catch { environment.workspacePlugin.statusMessage = error.localizedDescription }
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

private struct WorkspaceCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    let snapshot: WorkspaceCapture
    let save: (WorkspaceLayout) -> Void
    @State private var name: String
    @State private var selection: [String: UUID]
    @State private var foreground: String?

    init(snapshot: WorkspaceCapture, save: @escaping (WorkspaceLayout) -> Void) {
        self.snapshot = snapshot
        self.save = save
        _name = State(initialValue: snapshot.replacing?.name ?? "")
        let existing = snapshot.replacing.map { Set($0.entries.map(\.bundleID)) }
        _selection = State(initialValue: Dictionary(uniqueKeysWithValues: snapshot.applications.compactMap { app in
            guard existing?.contains(app.bundleID) ?? true, let first = app.windows.first else { return nil }
            return (app.bundleID, first.id)
        }))
        _foreground = State(initialValue: snapshot.replacing?.foregroundBundleID)
    }

    private var entries: [WorkspaceEntry] {
        snapshot.applications.compactMap { app in app.windows.first { $0.id == selection[app.id] }?.entry }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Save Current Workspace").font(.headline)
            TextField("Name", text: $name)
            Text("Each application restores its current main window, not a specific document.")
                .font(.caption).foregroundStyle(.secondary)
            List {
                ForEach(snapshot.applications) { app in
                    VStack(alignment: .leading) {
                        Toggle(app.name, isOn: Binding(get: { selection[app.id] != nil }, set: { enabled in
                            selection[app.id] = enabled ? app.windows.first?.id : nil
                            if !enabled, foreground == app.id { foreground = nil }
                        }))
                        if selection[app.id] != nil {
                            Picker("Layout window", selection: Binding(get: { selection[app.id] }, set: { selection[app.id] = $0 })) {
                                ForEach(app.windows) { window in
                                    Text("\(window.title) — \(window.entry.displayName)").tag(Optional(window.id))
                                }
                            }
                        }
                    }
                }
                if snapshot.applications.isEmpty { Text("No eligible windows on the current desktop.") }
                if !snapshot.notices.isEmpty {
                    DisclosureGroup("Skipped Windows") {
                        ForEach(snapshot.notices, id: \.self) { Text($0).font(.caption) }
                    }
                }
            }
            Picker("Activate after restoring", selection: $foreground) {
                Text("Do not activate").tag(String?.none)
                ForEach(entries) { entry in Text(entry.applicationName).tag(Optional(entry.bundleID)) }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save") {
                    let layout = WorkspaceLayout(id: snapshot.replacing?.id ?? UUID(),
                        name: name.trimmingCharacters(in: .whitespacesAndNewlines), entries: entries,
                        foregroundBundleID: entries.contains { $0.bundleID == foreground } ? foreground : nil)
                    save(layout)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || entries.isEmpty)
            }
        }
        .padding(20).frame(width: 560, height: 460)
    }
}
