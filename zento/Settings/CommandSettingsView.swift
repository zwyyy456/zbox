import SwiftUI

struct ShortcutSettingsView: View {
    let environment: AppEnvironment
    @State private var showingApplicationPicker = false
    @State private var query = ""
    @State private var onlyAssigned = false
    @State private var selection: CommandID?
    @State private var editingTarget: CommandShortcutTarget?

    private struct Row: Identifiable {
        let target: CommandShortcutTarget
        let source: String
        let supportsHotkey: Bool
        var id: CommandID { target.id }
    }

    private var allRows: [Row] {
        let shortcutIDs = Set(environment.commandShortcutTargets.map(\.id))
        return environment.commandConfigurationSections.flatMap { section in
            section.targets.map {
                Row(target: $0, source: section.title, supportsHotkey: shortcutIDs.contains($0.id))
            }
        }
    }

    private var rows: [Row] {
        allRows.filter {
            let alias = environment.aliasStore.aliases[$0.id]
            let configured = alias != nil || environment.commandHotkey(for: $0.id) != nil
            let visible = !ApplicationCommands.owns($0.id) || configured
            return visible && (query.isEmpty || $0.target.title.localizedStandardContains(query)
                || $0.source.localizedStandardContains(query)
                || (alias?.localizedStandardContains(query) ?? false))
                && (!onlyAssigned || configured)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Root Search", systemImage: "magnifyingglass")
                    Spacer()
                    ShortcutRecorder(
                        hotkey: environment.hotkeys.rootSearchHotkey, allowsClearing: false,
                        accessibilityLabel: String(localized: "Root Search shortcut"),
                        onChange: { if let hotkey = $0 { environment.hotkeys.setRootSearchHotkey(hotkey) } },
                        onInvalid: environment.hotkeys.reportInvalidRootSearchHotkey,
                        onRecordingChanged: environment.hotkeys.setShortcutRecordingActive
                    )
                    .frame(width: 140)
                }
                if let error = environment.hotkeys.rootSearchHotkeyError {
                    SettingsErrorView(message: error)
                }
                HStack(spacing: 12) {
                    TextField("Search Commands", text: $query)
                        .textFieldStyle(.roundedBorder)
                    Toggle("Only Show Assigned", isOn: $onlyAssigned)
                        .toggleStyle(.checkbox)
                        .fixedSize()
                    Button("Configure Application…") { showingApplicationPicker = true }
                }
            }
            .padding(16)

            if rows.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(rows, selection: $selection) {
                    TableColumn("Command") { row in
                        HStack(spacing: 8) {
                            if ApplicationCommands.owns(row.id) {
                                ApplicationConfigurationIcon(environment: environment, id: row.id)
                            }
                            Text(row.target.title)
                                .lineLimit(1)
                                .help(row.target.title)
                        }
                    }
                    .width(min: 160, ideal: 230)
                    TableColumn("Source") { row in
                        Text(row.source)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .help(row.source)
                    }
                    .width(min: 80, ideal: 110)
                    TableColumn("Alias") { row in
                        Button {
                            selection = row.id
                            editingTarget = row.target
                        } label: {
                            Text(environment.aliasStore.aliases[row.id] ?? String(localized: "Add…"))
                                .lineLimit(1)
                        }
                        .buttonStyle(.link)
                        .help("Edit Alias…")
                        .accessibilityLabel(String(localized: "Alias") + ": " + row.target.title)
                    }
                    .width(min: 70, ideal: 100)
                    TableColumn("Shortcut") { row in
                        if row.supportsHotkey {
                            shortcutRecorder(row.target)
                        } else {
                            Text("—").foregroundStyle(.tertiary)
                                .accessibilityLabel("Not Available")
                        }
                    }
                    .width(150)
                }
                .contextMenu(forSelectionType: CommandID.self) { ids in
                    if let id = ids.first, let row = rows.first(where: { $0.id == id }) {
                        Button("Edit Alias…") { editingTarget = row.target }
                    }
                } primaryAction: { ids in
                    if let id = ids.first { editingTarget = rows.first { $0.id == id }?.target }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Click an alias to edit it. Type the alias in Root Search, then press Return.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let error = selection.flatMap({ environment.hotkeys.commandHotkeyErrors[$0] })
                    ?? environment.hotkeys.shortcutRegistrationError {
                    SettingsErrorView(message: error)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .sheet(item: $editingTarget) { target in
            CommandConfigurationEditor(environment: environment, target: target)
        }
        .sheet(isPresented: $showingApplicationPicker) {
            ApplicationConfigurationPicker(environment: environment)
        }
        .onAppear(perform: openRequestedAlias)
        .onChange(of: environment.aliasSettingsTarget) { _, _ in openRequestedAlias() }
    }

    @ViewBuilder
    private var emptyState: some View {
        if !query.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            ContentUnavailableView("No Configured Commands", systemImage: "keyboard",
                description: Text("Turn off the filter to configure an alias or shortcut."))
        }
    }

    private func shortcutRecorder(_ target: CommandShortcutTarget) -> some View {
        ShortcutRecorder(
            hotkey: environment.commandHotkey(for: target.id), allowsClearing: true,
            accessibilityLabel: String(localized: "\(target.title) shortcut"),
            onChange: {
                selection = target.id
                environment.hotkeys.setCommandHotkey($0, for: target.id)
            },
            onInvalid: {
                selection = target.id
                environment.hotkeys.reportInvalidCommandHotkey($0, for: target.id)
            },
            onRecordingChanged: environment.hotkeys.setShortcutRecordingActive,
            presentation: .table,
            isSelected: selection == target.id
        )
        .frame(width: 140, height: 24)
    }

    private func openRequestedAlias() {
        guard let id = environment.aliasSettingsTarget else { return }
        environment.aliasSettingsTarget = nil
        onlyAssigned = false
        query = ""
        selection = id
        editingTarget = allRows.first { $0.id == id }?.target
    }
}

private struct CommandConfigurationEditor: View {
    let environment: AppEnvironment
    let target: CommandShortcutTarget
    var requiresConfiguration = false
    private var isApplication: Bool { ApplicationCommands.owns(target.id) }
    @State private var draftHotkey: Hotkey?
    @State private var isRecording = false
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var error: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isApplication ? String(localized: "Configure Application") : String(localized: "Edit Alias")).font(.headline)
            Text(target.title).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Alias", text: $draft)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit(save)
            if isApplication {
                LabeledContent("Shortcut") {
                    ShortcutRecorder(
                        hotkey: draftHotkey, allowsClearing: true,
                        accessibilityLabel: String(localized: "\(target.title) shortcut"),
                        onChange: { draftHotkey = $0; error = nil },
                        onInvalid: { error = $0 },
                        onRecordingChanged: {
                            isRecording = $0
                            environment.hotkeys.setShortcutRecordingActive($0)
                        }
                    )
                    .frame(width: 140)
                }
                Text("Set an alias, a shortcut, or both. Press Delete while recording to clear the shortcut.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Use a short name without spaces. Leave empty to remove the alias.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let error {
                Text(error).font(.callout).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isRecording || (requiresConfiguration && draftHotkey == nil && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }
        }
        .padding(20)
        .frame(width: 380)
        .defaultFocus($isFocused, true)
        .onAppear {
            draft = environment.aliasStore.aliases[target.id] ?? ""
            draftHotkey = environment.commandHotkey(for: target.id)
            isFocused = true
        }
    }

    private func save() {
        guard !isRecording,
              !requiresConfiguration || draftHotkey != nil || !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            if isApplication {
                try environment.setApplicationConfiguration(alias: draft, hotkey: draftHotkey, for: target.id)
            } else {
                try environment.aliasStore.set(draft, for: target.id)
            }
            dismiss()
        } catch CommandAliasStore.AliasError.conflict(let id) {
            let title = environment.commandConfigurationSections.flatMap(\.targets)
                .first { $0.id == id }?.title ?? id.rawValue
            error = String(localized: "Alias is already assigned to: \(title)")
        } catch CommandAliasStore.AliasError.invalid {
            error = String(localized: "Aliases cannot contain spaces or control characters.")
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct ApplicationConfigurationIcon: View {
    let environment: AppEnvironment
    let id: CommandID

    var body: some View {
        Group {
            if let icon = environment.applicationIcon(for: id) {
                Image(nsImage: icon).resizable()
            } else {
                Image(systemName: "app").resizable()
            }
        }
        .scaledToFit()
        .frame(width: 20, height: 20)
        .accessibilityHidden(true)
    }
}

private struct ApplicationConfigurationPicker: View {
    let environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selectedApplicationID: String?
    @State private var target: CommandShortcutTarget?
    @FocusState private var isSearchFocused: Bool

    private var applications: [ApplicationInfo] {
        environment.applications.filter {
            query.isEmpty || $0.name.localizedStandardContains(query)
                || ($0.bundleIdentifier?.localizedStandardContains(query) ?? false)
        }
    }

    var body: some View {
        if let target {
            CommandConfigurationEditor(environment: environment, target: target,
                requiresConfiguration: environment.aliasStore.aliases[target.id] == nil && environment.commandHotkey(for: target.id) == nil)
                .id(target.id)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                Text("Configure Application…").font(.headline)
                TextField("Search Applications", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .focused($isSearchFocused)
                    .onChange(of: query) { _, _ in selectedApplicationID = nil }
                List(applications, selection: $selectedApplicationID) { application in
                    let id = ApplicationCommands.id(for: application)
                    HStack(spacing: 10) {
                        ApplicationConfigurationIcon(environment: environment, id: id)
                        Text(application.name)
                        Spacer()
                        if let alias = environment.aliasStore.aliases[id] {
                            Text(alias).foregroundStyle(.secondary)
                        }
                    }
                    .tag(application.id)
                }
                .contextMenu(forSelectionType: String.self) { _ in
                } primaryAction: { ids in
                    if let id = ids.first { selectApplication(id) }
                }
                .overlay {
                    if applications.isEmpty {
                        ContentUnavailableView.search(text: query)
                    }
                }
                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                    Button("Continue") {
                        if let id = selectedApplicationID { selectApplication(id) }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedApplicationID == nil)
                }
            }
            .padding(20)
            .frame(width: 420, height: 440)
            .onAppear { isSearchFocused = true }
        }
    }
    private func selectApplication(_ id: String) {
        guard let application = applications.first(where: { $0.id == id }) else { return }
        target = CommandShortcutTarget(id: ApplicationCommands.id(for: application), title: application.name)
    }

}
