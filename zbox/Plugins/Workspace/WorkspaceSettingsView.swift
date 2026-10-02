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
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }
            if plugin.isRestoring || !plugin.results.isEmpty {
                Section("Latest Restoration") {
                    if plugin.isRestoring {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text(plugin.restoringName ?? "")
                            Spacer()
                            Button("Cancel", action: plugin.cancelRestore)
                        }
                    }
                    ForEach(plugin.results) { result in
                        LabeledContent(result.applicationName) {
                            Text(result.message).foregroundStyle(result.succeeded ? Color.secondary : Color.red)
                        }
                    }
                }
            }
            Section("Workspaces") {
                Button("Save Current Workspace") { capture() }
                    .disabled(!plugin.isEnabled || plugin.isRestoring)
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
                        Button("Restore") { environment.restoreWorkspace(layout) }
                            .disabled(!plugin.isEnabled || plugin.isRestoring)
                        Menu {
                            Button("Edit") { plugin.statusMessage = nil; editing = layout }
                            Button("Update from Current Layout") { capture(replacing: layout) }
                                .disabled(!plugin.isEnabled || plugin.isRestoring)
                        } label: { Image(systemName: "ellipsis") }
                        .menuStyle(.borderlessButton).fixedSize()
                        .accessibilityLabel("Workspace Actions")
                        .disabled(plugin.isRestoring)
                        Button("Delete", role: .destructive) { environment.deleteWorkspace(layout) }
                            .disabled(plugin.isRestoring)
                    }
                }
            }
        }
        .settingsPane()
        .sheet(item: $plugin.displayMapping) { request in
            WorkspaceDisplayMappingView(request: request) { mapping in
                plugin.restore(request.layout, mapping: mapping)
            }
        }
        .sheet(item: $plugin.capture) { snapshot in
            WorkspaceCaptureView(snapshot: snapshot, errorMessage: plugin.statusMessage) { layout in environment.saveWorkspace(layout) }
        }
        .sheet(item: $editing) { layout in
            WorkspaceEditor(layout: layout, errorMessage: plugin.statusMessage) { updated in
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
    let errorMessage: String?
    let save: (WorkspaceLayout) -> Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Workspace").font(.headline)
            TextField("Name", text: $layout.name)
            if let errorMessage { SettingsErrorView(message: errorMessage) }
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
                    if save(layout) { dismiss() }
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
    let errorMessage: String?
    let save: (WorkspaceLayout) -> Bool
    @State private var name: String
    @State private var selection: [String: UUID]
    @State private var foreground: String?

    init(snapshot: WorkspaceCapture, errorMessage: String?, save: @escaping (WorkspaceLayout) -> Bool) {
        self.errorMessage = errorMessage
        self.snapshot = snapshot
        self.save = save
        _name = State(initialValue: snapshot.replacing?.name ?? "")
        let existing = snapshot.replacing.map { Set($0.entries.map(\.bundleID)) }
        _selection = State(initialValue: Dictionary(uniqueKeysWithValues: snapshot.applications.compactMap { app in
            guard existing?.contains(app.bundleID) ?? true, let first = app.windows.first else { return nil }
            return (app.bundleID, first.id)
        }))
        let foreground = snapshot.replacing?.foregroundBundleID
        _foreground = State(initialValue: snapshot.applications.contains { $0.id == foreground } ? foreground : nil)
    }

    private var entries: [WorkspaceEntry] {
        snapshot.applications.compactMap { app in app.windows.first { $0.id == selection[app.id] }?.entry }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Save Current Workspace").font(.headline)
            TextField("Name", text: $name)
            if let errorMessage { SettingsErrorView(message: errorMessage) }
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
                                    Text(verbatim: "\(window.title) — \(window.entry.displayName)").tag(Optional(window.id))
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
                    if save(layout) { dismiss() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || entries.isEmpty)
            }
        }
        .padding(20).frame(width: 560, height: 460)
    }
}

private struct WorkspaceDisplayMappingView: View {
    @Environment(\.dismiss) private var dismiss
    let request: WorkspaceDisplayMapping
    let restore: ([String: String]) -> Void
    @State private var mapping: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose Displays").font(.headline)
            Text("Some saved displays are unavailable. Choose a display or skip their applications for this restoration only.")
                .foregroundStyle(.secondary)
            Form {
                ForEach(request.missing) { entry in
                    Picker(entry.displayName, selection: Binding(get: { mapping[entry.displayID] }, set: { mapping[entry.displayID] = $0 })) {
                        Text("Choose…").tag(String?.none)
                        Text("Skip applications").tag(Optional(""))
                        ForEach(request.displays.filter { WorkspaceDisplay.matching($0.id, in: request.displays) != nil }) { display in
                            Text(display.name).tag(Optional(display.id))
                        }
                    }
                }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Restore") { restore(mapping); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(request.missing.contains { mapping[$0.displayID] == nil })
            }
        }
        .padding(20).frame(width: 520)
    }
}
