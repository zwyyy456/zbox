import AppKit
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
    private(set) var lastCapture: TextLookupCapture?
    private(set) var captureError: TextCaptureError?

    init(
        settings: TextLookupSettingsStore,
        hotkeyRegistrar: GlobalHotkeyRegistrar,
        capturer: any TextCapturing = AccessibilityTextCapturer()
    ) {
        self.settings = settings
        self.hotkeyRegistrar = hotkeyRegistrar
        self.capturer = capturer
        triggerMonitor.onMouseDown = { [weak self] in self?.clearCandidate() }
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
        lastCapture = nil
        captureError = nil
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
        guard let request = captureRequest(intent: .pointerLocation(NSEvent.mouseLocation)) else {
            captureError = .unableToReadText
            return
        }
        beginCapture(request, reportFailure: true, completion: publish)
    }

    private func captureRequest(
        intent: TextCaptureIntent,
        fallbackAnchorPoint: CGPoint? = nil
    ) -> TextCaptureRequest? {
        guard let application = NSWorkspace.shared.frontmostApplication,
              let primaryScreenMaxY = NSScreen.screens.first?.frame.maxY else { return nil }
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
            fallbackAnchorPoint: fallbackAnchorPoint
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
                } catch let error as TextCaptureError
                    where self.settings.isClipboardFallbackEnabled
                        && request.fallbackAnchorPoint != nil
                        && [.noSelection, .unableToReadText, .unsupportedElement].contains(error) {
                    capture = try await self.clipboardCapturer.capture(request)
                }
                try Task.checkCancellation()
                guard self.captureAttemptID == request.id else { return }
                completion(capture)
            } catch is CancellationError {
                return
            } catch let error as TextCaptureError {
                guard self.captureAttemptID == request.id, reportFailure else { return }
                captureError = error
                statusMessage = error.localizedDescription
            } catch {
                guard self.captureAttemptID == request.id, reportFailure else { return }
                captureError = .unableToReadText
                statusMessage = TextCaptureError.unableToReadText.localizedDescription
            }
        }
    }

    private func publish(_ capture: TextLookupCapture) {
        lastCapture = capture
        captureError = nil
        statusMessage = nil
    }

    private func clearCandidate() {
        candidate = nil
        captureTask?.cancel()
        captureTask = nil
        captureAttemptID = nil
    }
}
