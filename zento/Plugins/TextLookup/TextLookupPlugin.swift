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
    private let ocr = TextLookupOCR()
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
            self?.cancelCapture()
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
        cancelCapture()
        panelController.hide()
        session.clear()
        captureAttemptID = request.id
        captureTask = Task { [weak self] in
            guard let self else { return }
            do {
                if let delay { try await Task.sleep(for: delay) }
                let capture = try await captureWithCompatibility(request)
                try Task.checkCancellation()
                guard self.captureAttemptID == request.id else { return }

                // Freeze the local crop before showing our popup. Recognition can finish later.
                var contextSnapshot: TextLookupOCRSnapshot?
                var contextMessage: String?
                if capture.needsContext && !capture.isContextFragment && settings.isLocalOCREnabled {
                    do {
                        contextSnapshot = try await TextLookupScreenCapture.snapshot(request, anchor: capture.anchorRect)
                    } catch is CancellationError { throw CancellationError() }
                    catch let error as TextCaptureError {
                        if error == .secureText || error == .excludedApplication || error == .permissionRequired { throw error }
                        contextMessage = error == .screenCapturePermissionRequired ? error.localizedDescription
                            : String(localized: "No matching context was found near this word.")
                    } catch {
                        contextMessage = String(localized: "The word was read, but local OCR could not capture its context.")
                    }
                }
                try Task.checkCancellation()
                guard self.captureAttemptID == request.id else { return }
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == request.targetApplicationPID else { return }
                completion(capture)
                session.setContextStatus(id: capture.id, loading: contextSnapshot != nil, message: contextMessage)
                if let contextSnapshot {
                    do {
                        let result = try await ocr.recognize(contextSnapshot, expectedTerm: capture.term)
                        try Task.checkCancellation()
                        guard self.captureAttemptID == request.id else { return }
                        guard settings.isLocalOCREnabled else {
                            session.setContextStatus(id: capture.id, loading: false, message: nil)
                            return
                        }
                        session.supplementContext(id: capture.id, term: capture.term, text: result.context,
                            isFragment: result.isFragment, targetLanguageIdentifier: settings.targetLanguageIdentifier)
                    } catch is CancellationError { return }
                    catch {
                        guard self.captureAttemptID == request.id else { return }
                        session.setContextStatus(id: capture.id, loading: false,
                            message: String(localized: "No matching context was found near this word."))
                    }
                }
            } catch is CancellationError {
                if self.captureAttemptID == request.id { self.panelController.hide() }
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

    private func captureWithCompatibility(_ request: TextCaptureRequest) async throws -> TextLookupCapture {
        do {
            return try await capturer.capture(request)
        } catch let error as TextCaptureError {
            guard error.allowsCompatibilityFallback else { throw error }
            _ = try TextLookupTargetAccess.validate(request)
            if request.intent.allowsClipboardFallback {
                if settings.isClipboardFallbackEnabled && error.allowsClipboardFallback {
                    do { return try await clipboardCapturer.capture(request) }
                    catch let copyError as TextCaptureError {
                        guard copyError.allowsCompatibilityFallback else { throw copyError }
                    }
                }
                // A selection failure must not silently look up a different word under the mouse.
                throw error
            }
            if settings.isDoubleClickFallbackEnabled {
                do {
                    if let capture = try await DoubleClickTextCapturer().capture(request, capturer: capturer,
                        clipboard: clipboardCapturer, allowClipboard: settings.isClipboardFallbackEnabled) {
                        return capture
                    }
                } catch let doubleClickError as TextCaptureError {
                    guard doubleClickError.allowsCompatibilityFallback else { throw doubleClickError }
                }
            }
            guard settings.isLocalOCREnabled else { throw error }
            let snapshot = try await TextLookupScreenCapture.snapshot(request, anchor: nil)
            session.beginOCR()
            try panelController.show(anchor: request.triggerAnchorRect)
            let result = try await ocr.recognize(snapshot)
            try Task.checkCancellation()
            _ = try TextLookupTargetAccess.validate(request)
            return TextLookupCapture(id: request.id, term: result.term, sentence: result.context,
                sourceURL: nil, anchorRect: result.bounds, isContextFragment: result.isFragment)
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
        if session.isRecognizingWord {
            panelController.hide()
        } else if let id = session.capture?.id {
            session.setContextStatus(id: id, loading: false, message: nil)
        }
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
