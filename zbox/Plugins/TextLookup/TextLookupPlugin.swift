import AppKit
import FlashDictIntegrationKit
import Observation

@MainActor
@Observable
final class TextLookupPlugin: BuiltinPlugin {
    static let pluginID = BuiltinPluginID(rawValue: "text-lookup")
    static let hotkeyRegistrationID = "plugin.text-lookup.lookup"

    let id = pluginID
    private let settings: TextLookupSettingsStore
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
        onDismiss: { [weak session] in session?.clear() }
    )

    private struct SelectionCandidate {
        let capture: TextLookupCapture
        let applicationBundleIdentifier: String?
        let createdAt: Date
    }

    private var candidate: SelectionCandidate?
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
        hotkeyRegistrar.unregister(id: Self.hotkeyRegistrationID)
        guard let hotkey = settings.shortcut.hotkey else { return }

        try hotkeyRegistrar.register(
            id: Self.hotkeyRegistrationID,
            hotkey: hotkey,
            label: settings.shortcut.label
        ) { [weak self] in
            self?.lookupShortcutPressed()
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
            guard let self else { return }
            if mode == .automatic {
                publish(capture)
            } else {
                candidate = SelectionCandidate(
                    capture: capture,
                    applicationBundleIdentifier: capture.sourceApplicationBundleIdentifier,
                    createdAt: Date()
                )
            }
        }
    }

    private func lookupShortcutPressed() {
        let frontmostBundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if let candidate,
           Date().timeIntervalSince(candidate.createdAt) <= 3,
           candidate.applicationBundleIdentifier == frontmostBundleIdentifier {
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
                          [.noSelection, .unableToReadText, .unsupportedElement].contains(error)
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
                statusMessage = error.localizedDescription
            } catch {
                guard self.captureAttemptID == request.id, reportFailure else { return }
                self.present(.unableToReadText, anchorPoint: request.triggerAnchorPoint)
                statusMessage = TextCaptureError.unableToReadText.localizedDescription
            }
        }
    }

    private func publish(_ capture: TextLookupCapture) {
        session.beginLookup(
            with: capture,
            targetLanguageIdentifier: settings.targetLanguageIdentifier
        )
        panelController.show(anchor: capture.anchorRect)
        statusMessage = nil
    }

    private func present(_ error: TextCaptureError, anchorPoint: CGPoint) {
        session.present(error)
        panelController.show(
            anchor: CGRect(x: anchorPoint.x, y: anchorPoint.y, width: 1, height: 1)
        )
    }

    private func clearCandidate() {
        candidate = nil
        captureTask?.cancel()
        captureTask = nil
        captureAttemptID = nil
    }
}
