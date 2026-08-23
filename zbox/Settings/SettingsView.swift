import SwiftUI

struct SettingsView: View {
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
                LabeledContent("Applications", value: "\(environment.applications.count)")

                Button("Reload Applications") {
                    environment.reloadApplications()
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

            Section("General") {
                Toggle(
                    "Launch at Login",
                    isOn: Binding(
                        get: { environment.isLaunchAtLoginEnabled },
                        set: { environment.setLaunchAtLoginEnabled($0) }
                    )
                )
            }

            TextLookupSettingsView(environment: environment)

            Section("Window Management") {
                Toggle(
                    "Enable Window Management",
                    isOn: Binding(
                        get: { environment.isWindowManagementEnabled },
                        set: { environment.setWindowManagementEnabled($0) }
                    )
                )
                Text("Window Management uses Accessibility only to move and resize the frontmost application window. Text Lookup has separate controls and privacy behavior above.")
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Request Permission") {
                        environment.requestAccessibilityPermission()
                    }
                    Button("Open System Settings") {
                        environment.openAccessibilitySettings()
                    }
                }
            }

            Text(environment.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 760)
        .scenePadding()
    }
}
