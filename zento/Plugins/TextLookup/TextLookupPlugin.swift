import AppKit
import FlashDictIntegrationKit
import Observation

@MainActor
@Observable
final class TextLookupPlugin {
    let settings: TextLookupSettingsStore
    private let hotkeyRegistrar: any HotkeyRegistering
    private let capturer: any TextCapturing
    private let isAccessibilityTrusted: @MainActor () -> Bool
    private let clipboardCapturer: ClipboardSelectionCapturer
    private let triggerMonitor = TextLookupTriggerMonitor()
    private let session: TextLookupSessionModel

    @ObservationIgnored
    private lazy var panelController = TextLookupPanelController(
        model: session,
        settings: settings,
        hotkeyRegistrar: hotkeyRegistrar,
        onDismiss: { [weak self] in self?.dismissSession() }
    )

    private var captureTask: Task<Void, Never>?
    private var captureAttemptID: UUID?

    private(set) var isRunning = false
    private(set) var statusMessage: String?

    init(
        settings: TextLookupSettingsStore,
        clipboardCoordinator: ClipboardAccessCoordinator,
        hotkeyRegistrar: any HotkeyRegistering,
        capturer: any TextCapturing = AccessibilityTextCapturer(),
        session: TextLookupSessionModel? = nil,
        isAccessibilityTrusted: @escaping @MainActor () -> Bool
    ) {
        clipboardCapturer = ClipboardSelectionCapturer(coordinator: clipboardCoordinator)
        self.settings = settings
        self.hotkeyRegistrar = hotkeyRegistrar
        self.capturer = capturer
        self.isAccessibilityTrusted = isAccessibilityTrusted
        self.session = session ?? TextLookupSessionModel(
            flashDict: try? FlashDictBridgeClient.production()
        )
        triggerMonitor.onMouseDown = { [weak self] in
            self?.panelController.hide()
        }
        triggerMonitor.onSelection = { [weak self] point, explicit in
            self?.lookupSelection(at: point, explicit: explicit)
        }
        triggerMonitor.onPointer = { [weak self] point in self?.lookupPointer(at: point) }
        triggerMonitor.ignoresWindow = { [weak self] window in self?.panelController.contains(window) == true }

    }

    func start() {
        guard !isRunning else { return }
        guard hasAccessibilityPermission else { return }
        isRunning = true
        do {
            try triggerMonitor.start()
            try reloadConfiguration()
            statusMessage = nil
        } catch {
            stop()
            settings.setEnabled(false)
            statusMessage = error.localizedDescription
        }
    }

    func stop() {
        guard isRunning else { return }
        captureTask?.cancel()
        captureTask = nil
        captureAttemptID = nil
        panelController.hide()
        triggerMonitor.stop()
        isRunning = false
        statusMessage = nil
    }

    func reloadConfiguration() throws {
        try settings.triggers.validate()
        triggerMonitor.configuration = settings.triggers
    }

    func setTriggers(_ value: TextLookupTriggers) throws {
        try value.validate()
        settings.setTriggers(value)
        triggerMonitor.configuration = value
    }

    func setShortcutRecordingActive(_ value: Bool) {
        triggerMonitor.isSuspended = value
        if value { cancelCapture() }
    }

    private func lookupSelection(at point: CGPoint, explicit: Bool) {
        guard hasAccessibilityPermission,
              let request = captureRequest(intent: .currentSelection, fallbackAnchorPoint: point) else { return }
        beginCapture(request, delay: explicit ? nil : .milliseconds(130), reportFailure: explicit) { [weak self] capture in
            guard let self,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == request.targetApplicationPID else { return }
            publish(capture)
        }
    }

    private func lookupPointer(at point: CGPoint) {
        guard hasAccessibilityPermission,
              let request = captureRequest(intent: .pointerLocation(point)) else { return }
        beginCapture(request, reportFailure: true, completion: publish)
    }

    private func captureRequest(
        intent: TextCaptureIntent,
        fallbackAnchorPoint: CGPoint? = nil
    ) -> TextCaptureRequest? {
        guard let application = NSWorkspace.shared.frontmostApplication,
              let primaryScreenMaxY = NSScreen.screens.first?.frame.maxY,
              let anchorPoint = fallbackAnchorPoint ?? intent.anchorPoint else { return nil }
        let excludedBundleIdentifiers = settings.excludedApplicationBundleIdentifiers
        let excludedApplicationPIDs: Set<pid_t> = Set(
            NSWorkspace.shared.runningApplications.compactMap { application in
                guard let bundleIdentifier = application.bundleIdentifier,
                      excludedBundleIdentifiers.contains(bundleIdentifier) else { return nil }
                return application.processIdentifier
            }
        )
        return TextCaptureRequest(
            id: UUID(),
            intent: intent,
            targetApplicationPID: application.processIdentifier,
            excludedApplicationPIDs: excludedApplicationPIDs,
            primaryScreenMaxY: primaryScreenMaxY,
            triggerAnchorPoint: anchorPoint
        )
    }

    func beginCapture(
        _ request: TextCaptureRequest,
        delay: Duration? = nil,
        reportFailure: Bool,
        completion: @escaping (TextLookupCapture) -> Void
    ) {
        panelController.hide()
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
                guard self.captureAttemptID == request.id else { return }
                if error == .permissionRequired {
                    self.disableForMissingAccessibilityPermission()
                    return
                }
                guard reportFailure else { return }
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

    private func cancelCapture() {
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

    private var hasAccessibilityPermission: Bool {
        guard isAccessibilityTrusted() else {
            disableForMissingAccessibilityPermission()
            return false
        }
        return true
    }

    private func disableForMissingAccessibilityPermission() {
        settings.setEnabled(false)
        stop()
        statusMessage = TextCaptureError.permissionRequired.localizedDescription
    }
}
