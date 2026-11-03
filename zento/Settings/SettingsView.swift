import SwiftUI

struct SettingsView: View {
    let environment: AppEnvironment
    @Environment(\.appearsActive) private var appearsActive

    var body: some View {
        @Bindable var environment = environment

        NavigationSplitView {
            List(selection: Binding<SettingsTab?>(
                get: { environment.selectedSettingsTab },
                set: { if let tab = $0 { environment.selectedSettingsTab = tab } }
            )) {
                settingsSection("Zento", tabs: [.general, .shortcuts, .extensions])
                settingsSection("Tools", tabs: [.fileSearch, .quicklinks, .snippets, .clipboardHistory,
                                                .screenshot, .textLookup, .scriptCommands])
                settingsSection("System", tabs: [.appMenu, .audio, .display, .workspace, .windowManagement])
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
        } detail: {
            settingsDetail
                .frame(minWidth: 600, maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(environment.selectedSettingsTab.title)
        }
        .frame(minWidth: 860, idealWidth: 940, maxWidth: .infinity,
               minHeight: 580, idealHeight: 660, maxHeight: .infinity)
        .background(SettingsWindowConfiguration(opener: environment.settingsWindowOpener))
    }

    private func settingsSection(_ title: LocalizedStringKey, tabs: [SettingsTab]) -> some View {
        Section(title) {
            ForEach(tabs, id: \.self) { tab in
                let isEnabled = environment.isPluginEnabled(tab)
                HStack {
                    Label {
                        Text(tab.title)
                    } icon: {
                        Image(systemName: tab.systemImage)
                            .foregroundStyle(sidebarIconColor(for: tab))
                    }
                    Spacer()
                    if let isEnabled {
                        Text(isEnabled ? String(localized: "On") : String(localized: "Off"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize()
                            .accessibilityHidden(true)
                    }
                }
                .tag(tab)
                .accessibilityValue(isEnabled.map { $0 ? String(localized: "On") : String(localized: "Off") } ?? "")
            }
        }
    }

    private func sidebarIconColor(for tab: SettingsTab) -> Color {
        // An explicit color keeps sidebar template images visible during activation.
        // The default sidebar tint briefly disappears when returning to this window.
        guard environment.selectedSettingsTab == tab else { return .accentColor }
        return Color(nsColor: appearsActive ? .alternateSelectedControlTextColor : .secondaryLabelColor)
    }

    @ViewBuilder
    private var settingsDetail: some View {
        switch environment.selectedSettingsTab {
        case .general: GeneralSettingsView(environment: environment)
        case .shortcuts: ShortcutSettingsView(environment: environment)
        case .extensions: ExtensionSettingsView(manager: environment.extensionManager)
        case .scriptCommands: ScriptCommandsSettingsView(environment: environment)
        case .fileSearch: FileSearchSettingsView(environment: environment)
        case .snippets: SnippetsSettingsView(environment: environment)
        case .quicklinks: QuicklinksSettingsView(environment: environment)
        case .appMenu: AppMenuSettingsView(environment: environment)
        case .audio: AudioSettingsView(environment: environment)
        case .display: DisplaySettingsView(environment: environment)
        case .workspace: WorkspaceSettingsView(environment: environment)
        case .windowManagement: WindowManagementSettingsView(environment: environment)
        case .clipboardHistory:
            ClipboardHistorySettingsView(plugin: environment.clipboardHistoryPlugin,
                                         onEnabledChanged: environment.setClipboardHistoryEnabled,
                                         shortcutError: environment.shortcutRegistrationError)
        case .screenshot:
            ScreenshotSettingsView(plugin: environment.screenshotPlugin,
                                   onEnabledChanged: environment.setScreenshotEnabled,
                                   shortcutError: environment.shortcutRegistrationError)
        case .textLookup:
            Form { TextLookupSettingsView(environment: environment) }.settingsPane()
        }
    }
}

private struct GeneralSettingsView: View {
    let environment: AppEnvironment

    var body: some View {
        @Bindable var environment = environment

        Form {
            Section("General") {
                Toggle(
                    "Launch at Login",
                    isOn: Binding(
                        get: { environment.isLaunchAtLoginEnabled },
                        set: { environment.setLaunchAtLoginEnabled($0) }
                    )
                )
                if let error = environment.launchAtLoginError {
                    SettingsErrorView(message: error)
                }
                Toggle(
                    "Show Application Paths in Search Results",
                    isOn: Binding(
                        get: { environment.showsApplicationPathsInSearchResults },
                        set: { environment.setShowsApplicationPathsInSearchResults($0) }
                    )
                )
                LabeledContent("Recent Commands") {
                    Button("Clear Recent Commands", action: environment.clearRecentCommands)
                        .disabled(environment.recentCommandIDs.isEmpty)
                }
            }

            Section("Applications") {
                LabeledContent("Indexed Applications", value: "\(environment.applications.count)")
                Button("Reload Applications") {
                    environment.reloadApplications()
                }
                if let error = environment.applicationReloadError {
                    SettingsErrorView(message: error)
                }
            }
        }
        .settingsPane()
    }
}

private struct ShortcutSettingsView: View {
    let environment: AppEnvironment
    @State private var query = ""
    @State private var onlyAssigned = false

    var body: some View {
        @Bindable var environment = environment

        let sections = environment.commandShortcutSections.compactMap { section in
            let targets = section.targets.filter {
                (query.isEmpty || $0.title.localizedStandardContains(query))
                    && (!onlyAssigned || environment.commandHotkey(for: $0.id) != nil)
            }
            return targets.isEmpty ? nil : (title: section.title, targets: targets)
        }

        VStack(spacing: 0) {
            HStack {
                TextField("Search Command Shortcuts", text: $query)
                    .textFieldStyle(.roundedBorder)
                Toggle("Only Show Assigned", isOn: $onlyAssigned)
                    .toggleStyle(.checkbox)
                    .fixedSize()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            Form {
                Section("Root Search") {
                    VStack(alignment: .leading, spacing: 6) {
                        LabeledContent("Global Hotkey") {
                            ShortcutRecorder(
                                hotkey: environment.rootSearchHotkey,
                                allowsClearing: false,
                                accessibilityLabel: String(localized: "Root Search shortcut"),
                                onChange: { hotkey in
                                    guard let hotkey else { return }
                                    environment.setRootSearchHotkey(hotkey)
                                },
                                onInvalid: environment.reportInvalidRootSearchHotkey,
                                onRecordingChanged: environment.setShortcutRecordingActive
                            )
                            .frame(width: 140)
                        }
                        if let error = environment.rootSearchHotkeyError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }

                if sections.isEmpty {
                    Section("Command Shortcuts") {
                        if query.isEmpty {
                            ContentUnavailableView("No Assigned Shortcuts", systemImage: "keyboard",
                                                   description: Text("Turn off the filter to assign a shortcut."))
                        } else {
                            ContentUnavailableView.search(text: query)
                        }
                    }
                }
                ForEach(sections, id: \.title) { section in
                    Section(section.title) {
                        ForEach(section.targets) { target in
                            commandShortcutRow(target)
                        }
                    }
                }

                if let error = environment.shortcutRegistrationError {
                    SettingsErrorView(message: error)
                }
            }
            .settingsPane()
        }
    }
}

/// Accessibility status with a request action shown only while permission is missing.
struct AccessibilityPermissionRow: View {
    let isTrusted: Bool
    let request: () -> Void
    let openSettings: () -> Void

    var body: some View {
        LabeledContent("Accessibility") {
            if isTrusted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label("Permission Required", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
        HStack {
            if !isTrusted {
                Button("Request Permission", action: request)
            }
            Button("Open System Settings", action: openSettings)
        }
    }
}

private extension ShortcutSettingsView {
    func commandShortcutRow(_ target: CommandShortcutTarget) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent(target.title) {
                ShortcutRecorder(
                    hotkey: environment.commandHotkey(for: target.id),
                    allowsClearing: true,
                    accessibilityLabel: String(localized: "\(target.title) shortcut"),
                    onChange: { hotkey in
                        environment.setCommandHotkey(hotkey, for: target.id)
                    },
                    onInvalid: { message in
                        environment.reportInvalidCommandHotkey(message, for: target.id)
                    },
                    onRecordingChanged: environment.setShortcutRecordingActive
                )
                .frame(width: 140)
            }
            if let error = environment.commandHotkeyErrors[target.id] {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}

struct SettingsErrorView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.red)
    }
}

extension View {
    func settingsPane() -> some View {
        formStyle(.grouped)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)
    }
}

// Settings finalizes its window style after attaching the content view.
private struct SettingsWindowConfiguration: NSViewRepresentable {
    let opener: SettingsWindowOpener

    func makeNSView(context: Context) -> WindowView {
        let view = WindowView()
        view.opener = opener
        return view
    }
    func updateNSView(_ nsView: WindowView, context: Context) {}

    final class WindowView: NSView {
        weak var opener: SettingsWindowOpener?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.toolbarStyle = .unifiedCompact
            opener?.attach(window)
            DispatchQueue.main.async { [weak window] in
                window?.styleMask.insert(.resizable)
            }
        }
    }
}
