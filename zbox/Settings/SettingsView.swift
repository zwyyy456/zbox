import SwiftUI

struct SettingsView: View {
    let environment: AppEnvironment

    var body: some View {
        Form {
            Section("Root Search") {
                LabeledContent("Global Hotkey", value: "⌥ Space")
                LabeledContent("Applications", value: "\(environment.applications.count)")

                Button("Reload Applications") {
                    environment.reloadApplications()
                }
            }

            Section("Window Management") {
                Text("Accessibility permission is needed to move other applications’ windows.")
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
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 300)
        .scenePadding()
    }
}
