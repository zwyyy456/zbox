import AppKit
import SwiftUI

struct MenuBarView: View {
    let environment: AppEnvironment

    var body: some View {
        Button {
            environment.toggleRootSearch()
        } label: {
            Text("\(String(localized: "Open zbox"))  \(HotkeyFormatter.displayName(for: environment.rootSearchHotkey))")
        }

        Button("Settings…") {
            do {
                try environment.settingsWindowOpener.open(source: "menu")
            } catch {
                NSAlert(error: error).runModal()
            }
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
