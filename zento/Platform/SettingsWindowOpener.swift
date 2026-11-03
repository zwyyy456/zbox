import AppKit

nonisolated enum SettingsWindowError: LocalizedError {
    case unavailable
    var errorDescription: String? { String(localized: "Settings could not be opened.") }
}

/// Bridges command execution to the SwiftUI Settings scene; never creates a window.
@MainActor
final class SettingsWindowOpener: NSObject {
    private var openAction: (@MainActor () -> Void)?
    private weak var window: NSWindow?
    private var awaitingWindow = false

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(windowWillClose(_:)),
                                               name: NSWindow.willCloseNotification, object: nil)
    }

    func bindOpenAction(_ action: @escaping @MainActor () -> Void) {
        openAction = action
    }

    func attach(_ window: NSWindow) {
        self.window = window
        window.toolbarStyle = .unifiedCompact
        window.titleVisibility = .hidden
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.awaitingWindow { self.presentWindow() }
        }
    }

    func open() throws {
        guard let openAction else { throw SettingsWindowError.unavailable }
        awaitingWindow = true
        openAction()
        if awaitingWindow, window != nil { presentWindow() }
    }

    private func presentWindow() {
        guard let window else { return }
        awaitingWindow = false
        NSApp.setActivationPolicy(.regular)
        WindowPresentation.present(window)
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let closed = notification.object as? NSWindow, closed === window else { return }
        awaitingWindow = false
        NSApp.setActivationPolicy(.accessory)
    }
}
