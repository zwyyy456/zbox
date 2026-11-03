import AppKit
import SwiftUI

struct MenuBarView: View {
    let environment: AppEnvironment

    var body: some View {
        Button("Open Zento") {
            environment.toggleRootSearch()
        }
        .keyboardShortcut(HotkeyFormatter.keyboardShortcut(for: environment.rootSearchHotkey))

        Button("Settings…") {
            do {
                try environment.settingsWindowOpener.open()
            } catch {
                NSAlert(error: error).runModal()
            }
        }

        Divider()

        Button("Reload Applications") {
            environment.reloadApplications()
        }

        Divider()

        Button("Quit Zento") {
            NSApplication.shared.terminate(nil)
        }
    }
}
