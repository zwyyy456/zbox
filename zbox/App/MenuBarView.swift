import AppKit
import SwiftUI

struct MenuBarView: View {
    let environment: AppEnvironment

    var body: some View {
        Button("Open ZBox") {
            environment.toggleRootSearch()
        }

        Text("Root Search: \(environment.rootSearchHotkey.label)")
            .foregroundStyle(.secondary)

        SettingsLink {
            Text("Settings…")
        }

        Divider()

        Button("Reload Applications") {
            environment.reloadApplications()
        }

        Text("\(environment.applications.count) applications")
            .foregroundStyle(.secondary)

        Divider()

        Button("Quit ZBox") {
            NSApplication.shared.terminate(nil)
        }
    }
}
