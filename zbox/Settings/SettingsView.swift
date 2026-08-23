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
                Picker(
                    "Global Hotkey",
                    selection: Binding(
                        get: { environment.rootSearchHotkey },
                        set: { environment.setRootSearchHotkey($0) }
                    )
                ) {
                    ForEach(HotkeyPreset.rootSearchChoices) { preset in
                        Text(preset.label).tag(preset)
                    }
                }
            }

            Section("Command Shortcuts") {
                ForEach(WindowCommands.shortcutTargets) { target in
                    Picker(
                        target.title,
                        selection: Binding(
                            get: { environment.commandHotkey(for: target.id) },
                            set: { environment.setCommandHotkey($0, for: target.id) }
                        )
                    ) {
                        ForEach(HotkeyPreset.allCases) { preset in
                            Text(preset.label).tag(preset)
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
                    value: environment.isAccessibilityTrusted ? "Granted" : "Required"
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
