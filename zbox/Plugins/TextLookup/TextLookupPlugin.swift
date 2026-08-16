import AppKit
import FlashDictIntegrationKit
import Observation

@MainActor
@Observable
final class TextLookupPlugin {
    static let hotkeyRegistrationID = "plugin.text-lookup.lookup"

    let settings: TextLookupSettingsStore
    private let hotkeyRegistrar: GlobalHotkeyRegistrar
    private let capturer: any TextCapturing
    private let clipboardCapturer = ClipboardSelectionCapturer()
    private let triggerMonitor = TextLookupTriggerMonitor()
    private let session: TextLookupSessionModel

    @ObservationIgnored
    private lazy var panelController = TextLookupPanelController(
        model: session,
        settings: settings,
        hotkeyRegistrar: hotkeyRegistrar,
        onDismiss: { [weak self] in self?.dismissSession() }
    )

    private var candidate: TextLookupSelectionCandidate?
    private var captureTask: Task<Void, Never>?
    private var captureAttemptID: UUID?

    private(set) var isRunning = false
    private(set) var statusMessage: String?

    init(
        settings: TextLookupSettingsStore,
        hotkeyRegistrar: GlobalHotkeyRegistrar,
        capturer: any TextCapturing = AccessibilityTextCapturer()
    ) {
        self.settings = settings
        self.hotkeyRegistrar = hotkeyRegistrar
        self.capturer = capturer
        session = TextLookupSessionModel(
            flashDict: try? FlashDictBridgeClient.production()
        )
        triggerMonitor.onMouseDown = { [weak self] in
            self?.panelController.hide()
            self?.clearCandidate()
        }
        triggerMonitor.onMouseUp = { [weak self] point in self?.mouseReleased(at: point) }
        triggerMonitor.onDoubleOption = { [weak self] in
            guard self?.settings.shortcut == .doubleOption else { return }
            self?.lookupShortcutPressed()
        }
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        triggerMonitor.start()
        do {
            try reloadConfiguration()
            statusMessage = nil
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func stop() {
        guard isRunning else { return }
        captureTask?.cancel()
        captureTask = nil
        captureAttemptID = nil
        candidate = nil
        panelController.hide()
        triggerMonitor.stop()
        hotkeyRegistrar.unregister(id: Self.hotkeyRegistrationID)
        isRunning = false
        statusMessage = nil
    }

    func reloadConfiguration() throws {
        guard isRunning else { return }
        let requests = settings.shortcut.hotkey.map { hotkey in
            [
                HotkeyRegistrationRequest(
                    id: Self.hotkeyRegistrationID,
                    hotkey: hotkey,
                    label: settings.shortcut.label
                ) { [weak self] in
                    self?.lookupShortcutPressed()
                },
            ]
        } ?? []
        try hotkeyRegistrar.replace(
            ids: [Self.hotkeyRegistrationID],
            with: requests
        )
    }

    func setShortcut(_ shortcut: TextLookupShortcutPreset) throws {
        let previous = settings.shortcut
        settings.setShortcut(shortcut)
        do {
            try reloadConfiguration()
        } catch {
            settings.setShortcut(previous)
            throw error
        }
    }

    private func mouseReleased(at point: CGPoint) {
        clearCandidate()
        guard settings.selectionMode != .off,
              let request = captureRequest(
                intent: .currentSelection,
                fallbackAnchorPoint: point
              ) else { return }

        let mode = settings.selectionMode
        beginCapture(request, delay: .milliseconds(130), reportFailure: false) { [weak self] capture in
            guard let self,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier
                    == request.targetApplicationPID else { return }
            if mode == .automatic {
                publish(capture)
            } else {
                candidate = TextLookupSelectionCandidate(
                    capture: capture,
                    targetApplicationPID: request.targetApplicationPID,
                    createdAt: Date()
                )
            }
        }
    }

    private func lookupShortcutPressed() {
        panelController.hide()
        let frontmostApplicationPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        if let candidate,
           candidate.isValid(
                at: Date(),
                frontmostApplicationPID: frontmostApplicationPID
           ) {
            self.candidate = nil
            publish(candidate.capture)
            return
        }

        candidate = nil
        let pointerLocation = NSEvent.mouseLocation
        guard let request = captureRequest(intent: .pointerLocation(pointerLocation)) else {
            present(.unableToReadText, anchorPoint: pointerLocation)
            return
        }
        session.beginCapture()
        do {
            try panelController.show(anchor: request.triggerAnchorRect)
        } catch {
            statusMessage = error.localizedDescription
            return
        }
        beginCapture(request, reportFailure: true, completion: publish)
    }

    private func captureRequest(
        intent: TextCaptureIntent,
        fallbackAnchorPoint: CGPoint? = nil
    ) -> TextCaptureRequest? {
        guard let application = NSWorkspace.shared.frontmostApplication,
              let primaryScreenMaxY = NSScreen.screens.first?.frame.maxY,
              let anchorPoint = fallbackAnchorPoint ?? intent.anchorPoint else { return nil }
        return TextCaptureRequest(
            id: UUID(),
            intent: intent,
            targetApplicationPID: application.processIdentifier,
            targetApplicationBundleIdentifier: application.bundleIdentifier,
            applicationBundleIdentifiersByPID: Dictionary(
                uniqueKeysWithValues: NSWorkspace.shared.runningApplications.compactMap { application in
                    application.bundleIdentifier.map { (application.processIdentifier, $0) }
                }
            ),
            excludedApplicationBundleIdentifiers: settings.excludedApplicationBundleIdentifiers,
            primaryScreenMaxY: primaryScreenMaxY,
            triggerAnchorPoint: anchorPoint
        )
    }

    private func beginCapture(
        _ request: TextCaptureRequest,
        delay: Duration? = nil,
        reportFailure: Bool,
        completion: @escaping (TextLookupCapture) -> Void
    ) {
        captureTask?.cancel()
        captureAttemptID = request.id
        captureTask = Task { [weak self, capturer] in
            guard let self else { return }
            do {
                if let delay { try await Task.sleep(for: delay) }
                let capture: TextLookupCapture
                do {
                    capture = try await capturer.capture(request)
                } catch let error as TextCaptureError {
                    guard self.settings.isClipboardFallbackEnabled,
                          request.intent.allowsClipboardFallback,
                          error.allowsClipboardFallback
                    else { throw error }
                    guard NSWorkspace.shared.frontmostApplication?.processIdentifier
                            == request.targetApplicationPID
                    else { throw TextCaptureError.unableToReadText }
                    capture = try await self.clipboardCapturer.capture(request)
                }
                try Task.checkCancellation()
                guard self.captureAttemptID == request.id else { return }
                completion(capture)
            } catch is CancellationError {
                return
            } catch let error as TextCaptureError {
                guard self.captureAttemptID == request.id, reportFailure else { return }
                self.present(error, anchorPoint: request.triggerAnchorPoint)
            } catch {
                guard self.captureAttemptID == request.id, reportFailure else { return }
                self.present(.unableToReadText, anchorPoint: request.triggerAnchorPoint)
            }
        }
    }

    private func publish(_ capture: TextLookupCapture) {
        do {
            try panelController.show(anchor: capture.anchorRect)
            session.beginLookup(
                with: capture,
                targetLanguageIdentifier: settings.targetLanguageIdentifier
            )
            statusMessage = nil
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func present(_ captureError: TextCaptureError, anchorPoint: CGPoint) {
        session.present(captureError)
        do {
            try panelController.show(
                anchor: CGRect(x: anchorPoint.x, y: anchorPoint.y, width: 1, height: 1)
            )
            statusMessage = captureError.localizedDescription
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func clearCandidate() {
        candidate = nil
        captureTask?.cancel()
        captureTask = nil
        captureAttemptID = nil
    }

    private func dismissSession() {
        captureTask?.cancel()
        captureTask = nil
        captureAttemptID = nil
        session.clear()
    }
}
