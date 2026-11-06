import AppKit
import SwiftUI

struct MenuBarView: View {
    let environment: AppEnvironment

    var body: some View {
        Button("Open Zento") {
            environment.showRootSearch()
        }
        .keyboardShortcut(HotkeyFormatter.keyboardShortcut(for: environment.hotkeys.rootSearchHotkey))

        ApplicationMenuItems(environment: environment)
    }
}

struct ApplicationMenuItems: View {
    let environment: AppEnvironment

    var body: some View {
        Button("Settings…") {
            do {
                environment.hideRootSearch()
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
