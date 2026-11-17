import AppKit
import FlashDictIntegrationKit
import Observation

@MainActor
@Observable
final class TextLookupPlugin {
    let settings: TextLookupSettingsStore
    private let capturer: any TextCapturing
    private let captureScreen: @MainActor (TextCaptureRequest, CGRect?) async throws -> TextLookupOCRSnapshot
    private let isAccessibilityTrusted: @MainActor () -> Bool
    private let clipboardCapturer: ClipboardSelectionCapturer
    private let ocr = TextLookupOCR()
    private let triggerMonitor = TextLookupTriggerMonitor()
    private let session: TextLookupSessionModel
    private let flashDictWindow: FlashDictWindowSession

    @ObservationIgnored
    private lazy var panelController = TextLookupPanelController(
        model: session,
        settings: settings,
        onDismiss: { [weak self] in self?.dismissSession() }
    )

    private var captureTask: Task<Void, Never>?
    private var captureAttemptID: UUID?

    var hasRemoteLookup: Bool { flashDictWindow.hasActiveWindowOrRequests }
    func waitForStop() async { await flashDictWindow.waitForStop() }
    private(set) var isRunning = false
    private(set) var statusMessage: String?

    init(
        settings: TextLookupSettingsStore,
        clipboardCoordinator: ClipboardAccessCoordinator,
        capturer: any TextCapturing = AccessibilityTextCapturer(),
        captureScreen: @escaping @MainActor (TextCaptureRequest, CGRect?) async throws -> TextLookupOCRSnapshot = {
            try await TextLookupScreenCapture.snapshot($0, anchor: $1)
        },
        session: TextLookupSessionModel? = nil,
        isAccessibilityTrusted: @escaping @MainActor () -> Bool
    ) {
        clipboardCapturer = ClipboardSelectionCapturer(coordinator: clipboardCoordinator)
        self.settings = settings
        self.capturer = capturer
        self.captureScreen = captureScreen
        self.isAccessibilityTrusted = isAccessibilityTrusted
        self.session = session ?? TextLookupSessionModel()
        self.session.translationSettings = settings.translation
        self.flashDictWindow = FlashDictWindowSession(client: try? FlashDictBridgeClient.production())
        self.flashDictWindow.onFailure = { [weak self] message, capture in
            guard let self, self.settings.dictionarySource == .flashDict else { return }
            self.flashDictWindow.dismiss()
            self.session.clear()
            self.session.integrationMessage = message
            self.session.retryIntegration = { [weak self] in self?.publish(capture) }
            do { try self.panelController.show(anchor: capture.anchorRect) }
            catch { self.statusMessage = error.localizedDescription }
        }
        self.flashDictWindow.onControlFailure = { [weak self] message in
            guard let self, self.isRunning, self.settings.dictionarySource == .flashDict else { return }
            self.statusMessage = message
        }
        triggerMonitor.onMouseDown = { [weak self] in
            self?.cancelCapture()
            self?.panelController.dismissForOutsideClick()
        }
        triggerMonitor.onSelection = { [weak self] point, explicit in
            self?.lookupSelection(at: point, explicit: explicit)
        }
        triggerMonitor.onPointer = { [weak self] point in self?.lookupPointer(at: point) }
        triggerMonitor.ignoresWindow = { [weak self] window in
            guard let self else { return false }
            if self.panelController.contains(window) { return true }
            return self.settings.dictionarySource == .flashDict && FlashDictLookupWindowAccess.containsMouse()
        }

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
        flashDictWindow.dismiss()
        triggerMonitor.stop()
        isRunning = false
        statusMessage = nil
    }

    func setDictionarySource(_ source: TextLookupDictionarySource) {
        guard settings.dictionarySource != source else { return }
        cancelCapture()
        panelController.hide()
        flashDictWindow.dismiss()
        settings.setDictionarySource(source)
    }

    static func openFlashDict(onFailure: @escaping @MainActor @Sendable (String) -> Void) {
#if DEBUG
        let bundleID = "tech.hyperseek.flashdict.dev"
#else
        let bundleID = "tech.hyperseek.flashdict"
#endif
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            onFailure(String(localized: "The matching FlashDict build is not installed."))
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in
            if error != nil {
                Task { @MainActor in onFailure(String(localized: "The matching FlashDict build could not be started.")) }
            }
        }
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
        flashDictWindow.dismiss()
        panelController.dismissForOutsideClick()
        session.clear()
        captureAttemptID = request.id
        captureTask = Task { [weak self] in
            guard let self else { return }
            do {
                if let delay { try await Task.sleep(for: delay) }
                // Release the previous remote window (and its temporary Escape key)
                // before any local OCR progress window is presented.
                await flashDictWindow.waitForStop()
                try Task.checkCancellation()
                let capture = try await captureWithCompatibility(request)
                try Task.checkCancellation()
                guard self.captureAttemptID == request.id else { return }

                // Freeze the local crop before showing our popup. Recognition can finish later.
                var contextSnapshot: TextLookupOCRSnapshot?
                var contextMessage: String?
                if capture.needsContext && !capture.isContextFragment && settings.isLocalOCREnabled {
                    do {
                        contextSnapshot = try await captureScreen(request, capture.anchorRect)
                    } catch is CancellationError { throw CancellationError() }
                    catch let error as TextCaptureError {
                        if error == .excludedApplication { throw error }
                        contextMessage = error == .screenCapturePermissionRequired ? error.localizedDescription
                            : String(localized: "No matching context was found near this word.")
                    } catch {
                        contextMessage = String(localized: "The word was read, but local OCR could not capture its context.")
                    }
                }
                try Task.checkCancellation()
                guard self.captureAttemptID == request.id else { return }
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == request.targetApplicationPID else {
                    throw CancellationError()
                }
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
                        if settings.dictionarySource == .flashDict {
                            flashDictWindow.supplement(capture, sentence: result.context, isFragment: result.isFragment)
                        } else {
                            session.supplementContext(id: capture.id, term: capture.term, text: result.context,
                                isFragment: result.isFragment, targetLanguageIdentifier: settings.targetLanguageIdentifier,
                                sourceLanguageIdentifier: settings.sourceLanguageIdentifier)
                        }
                    } catch is CancellationError { return }
                    catch {
                        guard self.captureAttemptID == request.id else { return }
                        session.setContextStatus(id: capture.id, loading: false,
                            message: String(localized: "No matching context was found near this word."))
                    }
                }
            } catch is CancellationError {
                if self.captureAttemptID == request.id {
                    self.flashDictWindow.dismiss()
                    self.session.clear()
                    self.panelController.dismissForOutsideClick()
                }
                return
            } catch let error as TextCaptureError {
                guard self.captureAttemptID == request.id else { return }
                if error == .permissionRequired {
                    self.disableForMissingAccessibilityPermission()
                    return
                }
                guard reportFailure else { return }
                self.flashDictWindow.dismiss()
                await self.flashDictWindow.waitForStop()
                guard self.captureAttemptID == request.id else { return }
                self.present(error, anchorPoint: request.triggerAnchorPoint)
            } catch let error as FlashDictIntegrationError {
                guard self.captureAttemptID == request.id, reportFailure else { return }
                self.flashDictWindow.dismiss()
                await self.flashDictWindow.waitForStop()
                guard self.captureAttemptID == request.id else { return }
                self.session.clear()
                self.session.integrationMessage = FlashDictWindowSession.message(error)
                self.session.retryIntegration = { [weak self] in self?.lookupPointer(at: request.triggerAnchorPoint) }
                do { try self.panelController.show(anchor: request.triggerAnchorRect) }
                catch { self.statusMessage = error.localizedDescription }
            } catch {
                guard self.captureAttemptID == request.id, reportFailure else { return }
                self.flashDictWindow.dismiss()
                await self.flashDictWindow.waitForStop()
                guard self.captureAttemptID == request.id else { return }
                self.present(.unableToReadText, anchorPoint: request.triggerAnchorPoint)
            }
        }
    }

    private func captureWithCompatibility(_ request: TextCaptureRequest) async throws -> TextLookupCapture {
        do {
            return try await capturer.capture(request)
        } catch let error as TextCaptureError {
            try TextLookupTargetAccess.validateSource(request)
            if request.intent.allowsClipboardFallback {
                guard error.allowsCompatibilityFallback else { throw error }
                if settings.isClipboardFallbackEnabled && error.allowsClipboardFallback {
                    _ = try TextLookupTargetAccess.validate(request)
                    do { return try await clipboardCapturer.capture(request) }
                    catch let copyError as TextCaptureError {
                        guard copyError.allowsCompatibilityFallback else { throw copyError }
                    }
                }
                // A selection failure must not silently look up a different word under the mouse.
                throw error
            }
            guard error.allowsCompatibilityFallback || error == .secureText else { throw error }
            if error.allowsCompatibilityFallback && settings.isDoubleClickFallbackEnabled {
                do {
                    if let capture = try await DoubleClickTextCapturer().capture(request, capturer: capturer,
                        clipboard: clipboardCapturer, allowClipboard: settings.isClipboardFallbackEnabled) {
                        return capture
                    }
                } catch let doubleClickError as TextCaptureError {
                    guard doubleClickError.allowsCompatibilityFallback || doubleClickError == .secureText else { throw doubleClickError }
                }
            }
            guard settings.isLocalOCREnabled else { throw error }
            let snapshot = try await captureScreen(request, nil)
            session.beginOCR()
            if settings.dictionarySource == .flashDict {
                try await flashDictWindow.beginRecognition(id: request.id, anchor: request.triggerAnchorRect)
            } else { try panelController.show(anchor: request.triggerAnchorRect) }
            let result = try await ocr.recognize(snapshot)
            try Task.checkCancellation()
            try TextLookupTargetAccess.validateSource(request)
            return TextLookupCapture(id: request.id, term: result.term, sentence: result.context,
                sourceURL: nil, anchorRect: result.bounds, isContextFragment: result.isFragment)
        }
    }

    private func publish(_ capture: TextLookupCapture) {
        if settings.dictionarySource == .flashDict {
            panelController.hide(notify: false)
            session.clear()
            flashDictWindow.present(capture)
            statusMessage = nil
            return
        }
        do {
            try panelController.show(anchor: capture.anchorRect)
            session.beginLookup(
                with: capture,
                targetLanguageIdentifier: settings.targetLanguageIdentifier,
                sourceLanguageIdentifier: settings.sourceLanguageIdentifier
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
            flashDictWindow.dismiss()
            session.clear()
            panelController.dismissForOutsideClick()
        } else if let id = session.capture?.id {
            session.setContextStatus(id: id, loading: false, message: nil)
        }
    }

    private func dismissSession() {
        flashDictWindow.dismiss()
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
