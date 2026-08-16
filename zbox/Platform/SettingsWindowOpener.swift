import AppKit

nonisolated enum SettingsWindowError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "Settings could not be opened."
    }
}

@MainActor
final class SettingsWindowOpener {
    func open() throws {
        let didOpen = NSApplication.shared.sendAction(
            Selector(("showSettingsWindow:")),
            to: nil,
            from: nil
        )
        guard didOpen else { throw SettingsWindowError.unavailable }
        NSApplication.shared.activate()
    }
}
