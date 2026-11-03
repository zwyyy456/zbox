import AppKit
import OSLog

nonisolated enum SettingsWindowError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        String(localized: "Settings could not be opened.")
    }
}

@MainActor
final class SettingsWindowOpener: NSObject {
    private let logger = Logger(subsystem: "tech.hyperseek.Zento", category: "SettingsWindow")
    private var openAction: (@MainActor () -> Void)?
    private weak var window: NSWindow?
    private var awaitingWindow = false

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(windowWillClose(_:)),
                                               name: NSWindow.willCloseNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(windowDidBecomeKey(_:)),
                                               name: NSWindow.didBecomeKeyNotification, object: nil)
    }

    func bindOpenAction(_ action: @escaping @MainActor () -> Void) {
        openAction = action
    }

    func attach(_ window: NSWindow) {
        self.window = window
        // Finish SwiftUI's window attachment before changing its focus and ordering.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.awaitingWindow { self.presentWindow() }
            else if self.window?.isVisible == true { NSApp.setActivationPolicy(.regular) }
        }
    }

    func open() throws {
        guard let openAction else {
            logger.error("Settings open action is unavailable")
            throw SettingsWindowError.unavailable
        }
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

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        guard let changedWindow = notification.object as? NSWindow, changedWindow === window else { return }
        NSApp.setActivationPolicy(.regular)
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let changedWindow = notification.object as? NSWindow, changedWindow === window else { return }
        awaitingWindow = false
        NSApp.setActivationPolicy(.accessory)
        // SwiftUI can retain and reuse the closed window without reattaching its view.
        // Keep the weak reference; it clears automatically if the window is released.
    }
}
