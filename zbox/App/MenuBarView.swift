import AppKit
import SwiftUI

struct MenuBarView: View {
    @Environment(\.openSettings) private var openSettings
    let environment: AppEnvironment

    var body: some View {
        Button {
            environment.toggleRootSearch()
        } label: {
            Text("\(String(localized: "Open zbox"))  \(HotkeyFormatter.displayName(for: environment.rootSearchHotkey))")
        }

        Button("Settings…") {
            openSettings()
            NSApplication.shared.activate()
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
