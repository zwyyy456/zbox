import AppKit
import SwiftUI

struct MenuBarView: View {
    let environment: AppEnvironment

    var body: some View {
        Button("Open zbox") {
            environment.toggleRootSearch()
        }

        Text("Root Search: \(HotkeyFormatter.displayName(for: environment.rootSearchHotkey))")
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

        Button("Quit zbox") {
            NSApplication.shared.terminate(nil)
        }
    }
}
