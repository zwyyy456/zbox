import SwiftUI

/// Commands are installed independently of whether the status item is inserted.
struct SettingsSceneCommands: Commands {
    @Environment(\.openSettings) private var openSettings
    let opener: SettingsWindowOpener

    var body: some Commands {
        // Only update this non-observable bridge. No scene or view state is mutated.
        let _ = opener.bindOpenAction { [openSettings] in openSettings() }
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                do { try opener.open() }
                catch { NSAlert(error: error).runModal() }
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}
