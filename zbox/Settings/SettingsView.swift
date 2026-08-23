import SwiftUI

struct SettingsView: View {
    let environment: AppEnvironment

    var body: some View {
        @Bindable var environment = environment

        TabView(selection: $environment.selectedSettingsTab) {
            GeneralSettingsView(environment: environment)
                .settingsTab(SettingsTab.general)

            ShortcutSettingsView(environment: environment)
                .settingsTab(SettingsTab.shortcuts)

            WindowManagementSettingsView(environment: environment)
                .settingsTab(SettingsTab.windowManagement)

            Form {
                TextLookupSettingsView(environment: environment)
                SettingsStatusView(message: environment.statusMessage)
            }
            .settingsPane()
            .settingsTab(SettingsTab.textLookup)
        }
        .frame(width: 600, height: 520)
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
            }

            SettingsStatusView(message: environment.statusMessage)
        }
        .settingsPane()
    }
}

private struct ShortcutSettingsView: View {
    let environment: AppEnvironment

    var body: some View {
        @Bindable var environment = environment

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
                ForEach(WindowCommands.shortcutTargets) { target in
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

            SettingsStatusView(message: environment.statusMessage)
        }
        .settingsPane()
    }
}

private struct WindowManagementSettingsView: View {
    let environment: AppEnvironment

    var body: some View {
        @Bindable var environment = environment

        Form {
            Section("Window Management") {
                Toggle(
                    "Enable Window Management",
                    isOn: Binding(
                        get: { environment.isWindowManagementEnabled },
                        set: { environment.setWindowManagementEnabled($0) }
                    )
                )
                Text("Window Management uses Accessibility only to move and resize the frontmost application window.")
                    .foregroundStyle(.secondary)
            }

            Section("Accessibility") {
                LabeledContent(
                    "Permission",
                    value: environment.isAccessibilityTrusted
                        ? String(localized: "Granted")
                        : String(localized: "Required")
                )
                HStack {
                    Button("Request Permission") {
                        environment.requestAccessibilityPermission()
                    }
                    Button("Open System Settings") {
                        environment.openAccessibilitySettings()
                    }
                }
            }

            SettingsStatusView(message: environment.statusMessage)
        }
        .settingsPane()
    }
}

private struct SettingsStatusView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

private extension View {
    func settingsPane() -> some View {
        formStyle(.grouped)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)
    }

    func settingsTab(_ tab: SettingsTab) -> some View {
        tabItem {
            Label(tab.title, systemImage: tab.systemImage)
        }
        .tag(tab)
    }
}
