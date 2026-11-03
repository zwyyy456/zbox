import SwiftUI

struct WindowManagementSettingsView: View {
    let environment: AppEnvironment

    var body: some View {
        @Bindable var environment = environment

        Form {
            Section("Window Management") {
                Toggle(
                    "Enable Window Management",
                    isOn: Binding(
                        get: { environment.windowManagementPlugin.isEnabled },
                        set: { environment.setWindowManagementEnabled($0) }
                    )
                )
                Text("Window Management uses Accessibility only to move and resize the frontmost application window.")
                    .foregroundStyle(.secondary)
            }

            Section("Accessibility") {
                AccessibilityPermissionRow(isTrusted: environment.isAccessibilityTrusted,
                                           request: environment.requestAccessibilityPermission,
                                           openSettings: environment.openAccessibilitySettings)
            }

            if let error = environment.windowManagementPlugin.statusMessage {
                SettingsErrorView(message: error)
            }
        }
        .settingsPane()
    }
}

