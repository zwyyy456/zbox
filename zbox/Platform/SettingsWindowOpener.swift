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
    private let logger = Logger(subsystem: "tech.hyperseek.zbox", category: "SettingsWindow")
    private var openAction: (@MainActor () -> Void)?
    private weak var window: NSWindow?
    private var request = 0
    private var awaitingWindow = false
    private var openingTask: Task<Void, Never>?

    override init() {
        super.init()
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(applicationStateChanged(_:)),
                                                   name: name, object: NSApp)
        }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                     NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification,
                     NSWindow.willCloseNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(windowStateChanged(_:)),
                                                   name: name, object: nil)
        }
    }

    func bindOpenAction(_ action: @escaping @MainActor () -> Void) {
        if openAction == nil { log("action-bound") }
        openAction = action
    }

    func attach(_ window: NSWindow) {
        self.window = window
        log("window-attached")
        // Finish SwiftUI's window attachment before changing its focus and ordering.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.awaitingWindow else { return }
            self.presentWindow()
        }
    }

    func open(source: String = "command") throws {
        guard let openAction else {
            logger.error("Settings open action is unavailable")
            throw SettingsWindowError.unavailable
        }
        request += 1
        let currentRequest = request
        logger.info("request=\(currentRequest) source=\(source, privacy: .public)")
        log("open-requested")

        openingTask?.cancel()
        awaitingWindow = false
        openingTask = Task { [weak self] in
            guard let self else { return }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            configuration.addsToRecentItems = false
            // Several development builds can share the bundle ID. Activate this installation.
            configuration.allowsRunningApplicationSubstitution = false
            self.log("workspace-activation-requested")
            do {
                let application = try await NSWorkspace.shared.openApplication(
                    at: Bundle.main.bundleURL, configuration: configuration
                )
                guard !Task.isCancelled, self.request == currentRequest else { return }
                self.logger.info("request=\(currentRequest) workspace-completed sameProcess=\(application.processIdentifier == ProcessInfo.processInfo.processIdentifier) runningActive=\(application.isActive)")
                self.log("workspace-activation-completed")
                self.awaitingWindow = true
                openAction()
                if self.awaitingWindow, self.window != nil { self.presentWindow() }
                self.log("open-action-returned")
            } catch {
                guard !Task.isCancelled, self.request == currentRequest else { return }
                let failure = error as NSError
                self.logger.error("request=\(currentRequest) workspace-activation-failed domain=\(failure.domain, privacy: .public) code=\(failure.code)")
                NSAlert(error: SettingsWindowError.unavailable).runModal()
            }
            self.openingTask = nil
        }
    }

    private func presentWindow() {
        guard let window else { return }
        awaitingWindow = false
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        log("window-presented")
    }

    @objc private func applicationStateChanged(_ notification: Notification) {
        guard request > 0 else { return }
        log(notification.name.rawValue)
    }

    @objc private func windowStateChanged(_ notification: Notification) {
        guard let changedWindow = notification.object as? NSWindow, changedWindow === window else { return }
        log(notification.name.rawValue)
        if notification.name == NSWindow.willCloseNotification {
            openingTask?.cancel()
            openingTask = nil
            awaitingWindow = false
            // SwiftUI can retain and reuse the closed window without reattaching its view.
            // Keep the weak reference; it clears automatically if the window is released.
        }
    }

    private func log(_ event: String) {
        logger.info("request=\(self.request) event=\(event, privacy: .public) active=\(NSApp.isActive) window=\(self.window != nil) visible=\(self.window?.isVisible ?? false) key=\(self.window?.isKeyWindow ?? false) main=\(self.window?.isMainWindow ?? false) miniaturized=\(self.window?.isMiniaturized ?? false)")
    }
}
