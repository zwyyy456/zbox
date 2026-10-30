import SwiftUI

struct SettingsView: View {
    let environment: AppEnvironment

    var body: some View {
        @Bindable var environment = environment

        NavigationSplitView {
            List(selection: Binding<SettingsTab?>(
                get: { environment.selectedSettingsTab },
                set: { if let tab = $0 { environment.selectedSettingsTab = tab } }
            )) {
                settingsSection("zbox", tabs: [.general, .shortcuts, .extensions])
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
        .background(SettingsWindowConfiguration())
    }

    private func settingsSection(_ title: LocalizedStringKey, tabs: [SettingsTab]) -> some View {
        Section(title) {
            ForEach(tabs, id: \.self) { tab in
                Label(tab.title, systemImage: tab.systemImage)
                    .tag(tab)
            }
        }
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

    var body: some View {
        @Bindable var environment = environment

        let targets = environment.commandShortcutTargets.filter {
            query.isEmpty || $0.title.localizedStandardContains(query)
        }

        VStack(spacing: 0) {
            TextField("Search Command Shortcuts", text: $query)
                .textFieldStyle(.roundedBorder)
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
                            .frame(width: 180)
                        }
                        if let error = environment.rootSearchHotkeyError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }

                Section("Command Shortcuts") {
                    if targets.isEmpty {
                        ContentUnavailableView.search(text: query)
                    }
                    ForEach(targets) { target in
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
                                        environment.reportInvalidCommandHotkey(
                                            message,
                                            for: target.id
                                        )
                                    },
                                    onRecordingChanged: environment.setShortcutRecordingActive
                                )
                                .frame(width: 180)
                            }
                            if let error = environment.commandHotkeyErrors[target.id] {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
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
    func makeNSView(context: Context) -> WindowView { WindowView() }
    func updateNSView(_ nsView: WindowView, context: Context) {}

    final class WindowView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.toolbarStyle = .unifiedCompact
            DispatchQueue.main.async { [weak window] in
                window?.styleMask.insert(.resizable)
            }
        }
    }
}
