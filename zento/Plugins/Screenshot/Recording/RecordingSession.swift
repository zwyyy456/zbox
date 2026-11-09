import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class RecordingSession: NSObject, NSWindowDelegate {
    enum State {
        case selecting(RecordingTargetKind?)
        case countdown(Int)
        case starting
        case recording(ContinuousClock.Instant)
        case finishing
        case preview(URL, saved: URL?)
        case discarding
        case failed(String)
        case closed
    }

    var targetKind = RecordingTargetKind.region
    let kind: RecordingKind
    private(set) var state = State.selecting(nil)
    private(set) var status: String?
    private(set) var isClosing = false
    private(set) var isSaving = false
    private(set) var previewPixelSize = CGSize.zero
    private(set) var previewNaturalSize = CGSize.zero
    var options: RecordingOptions {
        didSet { defaults.set(try? JSONEncoder().encode(options), forKey: kind.optionsKey) }
    }

    @ObservationIgnored private var controlHasBeenSized = false
    @ObservationIgnored private var previewWindow: NSWindow?
    @ObservationIgnored private var previewHasBeenSized = false
    @ObservationIgnored private var previewAvailableSize = CGSize.zero
    @ObservationIgnored private var confirmationAlert: NSAlert?
    @ObservationIgnored private let window: RecordingPanel
    @ObservationIgnored private let targetSelection = RecordingTargetSelection()
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let canBeginCapture: @MainActor () -> Bool
    @ObservationIgnored private let didClose: @MainActor () -> Void
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var recorder: ScreenRecorder?
    @ObservationIgnored private var countdown: Task<Void, Never>?
    @ObservationIgnored private var gifDeadline: Task<Void, Never>?
    @ObservationIgnored private var directory: URL?
    @ObservationIgnored private var stopWhenStarted = false

    private var activeWindow: NSWindow { previewWindow ?? window }

    var canStop: Bool {
        if case .recording = state { return true }
        return false
    }

    var blocksCapture: Bool {
        switch state {
        case .countdown, .starting, .recording, .finishing, .discarding: true
        case .selecting, .preview, .failed, .closed: false
        }
    }

    init(kind: RecordingKind, defaults: UserDefaults, canBeginCapture: @escaping @MainActor () -> Bool, didClose: @escaping @MainActor () -> Void) {
        self.kind = kind
        self.defaults = defaults
        self.canBeginCapture = canBeginCapture
        self.didClose = didClose
        options = RecordingOptions(kind: kind, saved: defaults.data(forKey: kind.optionsKey))
        window = RecordingPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
        super.init()
        window.delegate = self
        window.title = kind.title
        window.isReleasedWhenClosed = false
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let hosting = NSHostingView(rootView: RecordingWindowView(session: self))
        hosting.sizingOptions = []
        window.contentView = hosting
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
    }

    func updateControlSize(_ size: CGSize) {
        guard previewWindow == nil, confirmationAlert == nil else { return }
        let topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
        window.setContentSize(NSSize(width: ceil(size.width), height: ceil(size.height)))
        if controlHasBeenSized {
            window.setFrameTopLeftPoint(topLeft)
        } else {
            window.center()
            controlHasBeenSized = true
        }
    }

    func updatePreviewFooterSize(_ measuredSize: CGSize) {
        guard let previewWindow else { return }
        let footer = CGSize(width: ceil(measuredSize.width), height: ceil(measuredSize.height) + 1)
        previewWindow.contentMinSize = CGSize(width: 1, height: footer.height + 1)
        guard !previewHasBeenSized else { return }
        let size = RecordingPreviewLayout.initialContentSize(natural: previewNaturalSize, footer: footer, available: previewAvailableSize)
        previewWindow.setContentSize(size)
        // A narrower canvas can wrap the footer. Wait for its final width and height before presenting.
        // AppKit rounds requested sizes; compare with the resulting content width, not the fractional request.
        guard abs(measuredSize.width - previewWindow.contentLayoutRect.width) < 0.5 else { return }
        previewWindow.center()
        previewHasBeenSized = true
        window.orderOut(nil)
        WindowPresentation.present(previewWindow)
    }

    private func showPreview() {
        guard previewWindow == nil, confirmationAlert == nil else { return }
        let preview = NSWindow(contentRect: CGRect(origin: window.frame.origin, size: .zero), styleMask: [.titled, .closable, .miniaturizable, .resizable],
                               backing: .buffered, defer: false)
        let screen = window.screen ?? NSScreen.main!
        previewAvailableSize = preview.contentRect(forFrameRect: screen.visibleFrame.insetBy(dx: 16, dy: 16)).size
        preview.title = kind.title
        preview.isReleasedWhenClosed = false
        preview.delegate = self
        previewWindow = preview
        let hosting = NSHostingView(rootView: RecordingPreviewView(session: self))
        hosting.sizingOptions = []
        preview.contentView = hosting
        // Measure the footer at the content width before showing the window.
        preview.setContentSize(previewNaturalSize)
        hosting.layoutSubtreeIfNeeded()
    }

    func present() {
        if case .selecting(.some) = state { return }
        if case .closed = state { return }
        if case .preview = state { showPreview() }
        if let sheet = activeWindow.attachedSheet {
            sheet.makeKeyAndOrderFront(nil)
        } else {
            if previewWindow != nil {
                if previewHasBeenSized { WindowPresentation.present(activeWindow) }
            } else {
                if let content = window.contentView {
                    content.layoutSubtreeIfNeeded()
                    updateControlSize(content.fittingSize)
                }
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
        }
    }

    func showCaptureBlocked() {
        status = String(localized: "Finish or cancel the recording session before taking a screenshot.")
        present()
    }

    func choose(_ target: RecordingTargetKind) {
        guard case .selecting(nil) = state else { return }
        guard checkCaptureAvailable() else { return }
        status = nil
        state = .selecting(target)
        let windowID = CGWindowID(window.windowNumber)
        window.orderOut(nil)
        targetSelection.choose(target, excluding: windowID) { [weak self] result in
            guard let self, case .selecting(let selected) = state, selected == target else { return }
            switch result {
            case .success(let target?):
                startRecording(target)
            case .success(nil):
                chooseAgain()
            case .failure(let error):
                chooseAgain()
                status = error.localizedDescription
            }
            present()
        }
    }

    func chooseAgain() {
        targetSelection.cancel()
        status = nil
        state = .selecting(nil)
    }

    func prepareForScreenshot() {
        if case .selecting(.some) = state {
            chooseAgain()
            present()
        }
    }

    private func checkCaptureAvailable() -> Bool {
        guard canBeginCapture() else {
            status = RecordingError.captureInProgress.localizedDescription
            return false
        }
        return true
    }

    func startRecording(_ target: RecordingTarget) {
        guard case .selecting = state, operation == nil else { return }
        guard checkCaptureAvailable() else {
            state = .selecting(nil)
            return
        }
        let options = options
        status = nil
        let delay = kind == .gif ? options.selectedStartDelay : .threeSeconds
        state = delay == .immediately ? .starting : .countdown(delay.rawValue)
        if delay != .immediately {
            countdown = Task {
                for seconds in (1...delay.rawValue).reversed() {
                    guard case .countdown = state, !Task.isCancelled else { return }
                    state = .countdown(seconds)
                    do { try await Task.sleep(for: .seconds(1)) }
                    catch { return }
                }
            }
        }
        previewPixelSize = options.outputSize(for: target.pixelSize, kind: kind)
        previewNaturalSize = RecordingPreviewLayout.naturalSize(pixels: previewPixelSize, captureScale: target.pointPixelScale)
        operation = Task {
            defer { operation = nil; countdown = nil }
            do {
                try Task.checkCancellation()
                await countdown?.value
                try Task.checkCancellation()
                state = .starting
                let filter = try await target.captureFilter(excluding: CGWindowID(window.windowNumber))
                try Task.checkCancellation()

                let directory = try await RecordingFiles.makeSessionDirectory()
                self.directory = directory
                try Task.checkCancellation()
                let result = directory.appending(path: kind == .gif ? "Recording.gif" : "Recording.mp4")
                let recorder = try ScreenRecorder(target: target, filter: filter, options: options, kind: kind, url: result)
                self.recorder = recorder
                window.orderOut(nil)
                do {
                    try await recorder.record(started: didStartRecording) {
                        if case .discarding = state { return }
                        state = .finishing
                        status = nil
                        gifDeadline?.cancel()
                        window.orderFrontRegardless()
                    }
                } catch {
                    self.recorder = nil
                    throw error
                }
                self.recorder = nil
                gifDeadline?.cancel()
                gifDeadline = nil
                targetSelection.cancel()
                if case .discarding = state { throw CancellationError() }
                state = .finishing
                status = nil
                window.orderFrontRegardless()
                if kind == .video {
                    try await RecordingFiles.validateVideo(result, size: options.outputSize(for: target.pixelSize, kind: kind))
                }
                try Task.checkCancellation()
                status = nil
                state = .preview(result, saved: nil)
                present()
            } catch {
                gifDeadline?.cancel()
                gifDeadline = nil
                targetSelection.cancel()
                if case .discarding = state {
                    await finishDiscarding()
                } else {
                    let message = error.localizedDescription
                    // Cleanup may suspend while the user requests discard.
                    let cleanupError = await cleanDirectory()
                    if case .discarding = state {
                        finishClosing(cleanupError: cleanupError)
                    } else {
                        state = .failed(message)
                        status = cleanupError
                        dismissCloseConfirmation()
                        present()
                    }
                }
            }
        }
    }

    func startImmediately() {
        guard case .countdown = state else { return }
        state = .starting
        countdown?.cancel()
    }

    private func didStartRecording() {
        guard case .starting = state else { return }
        let started = ContinuousClock.now
        state = .recording(started)
        window.orderFrontRegardless()
        if stopWhenStarted {
            stopRecording()
        } else if kind == .gif {
            gifDeadline = Task { [weak self] in
                do { try await Task.sleep(until: started + .seconds(RecordingOptions.gifLimit), clock: .continuous) }
                catch { return }
                self?.stopRecording()
            }
        }
    }

    func stopRecording() {
        guard canStop else { return }
        state = .finishing
        status = nil
        gifDeadline?.cancel()
        recorder?.requestStop()
    }

    func discard() {
        guard !isSaving else { return }
        switch state {
        case .discarding, .closed: return
        default: break
        }
        state = .discarding
        countdown?.cancel()
        status = nil
        gifDeadline?.cancel()
        targetSelection.cancel()
        if let operation {
            if let recorder { recorder.requestStop(discard: true) }
            else { operation.cancel() }
        } else {
            operation = Task {
                await finishDiscarding()
                operation = nil
            }
        }
    }

    func save() {
        guard !isClosing, !isSaving else { return }
        Task { _ = await saveResult() }
    }

    private func saveResult() async -> Bool {
        guard case .preview(let source, _) = state, !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }
        status = nil
        let panel = NSSavePanel()
        panel.allowedContentTypes = [kind.fileType]
        panel.nameFieldStringValue = "Recording-\(Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash)))-\(UUID().uuidString.prefix(8)).\(source.pathExtension)"
        guard await panel.beginSheetModal(for: activeWindow) == .OK, let destination = panel.url else { return false }
        do {
            try await RecordingFiles.save(source, to: destination,
                                          replaceExisting: FileManager.default.fileExists(atPath: destination.path))
            state = .preview(source, saved: destination)
            return true
        } catch {
            status = error.localizedDescription
            return false
        }
    }

    private func dismissCloseConfirmation() {
        guard let alert = confirmationAlert, let parent = alert.window.sheetParent else { return }
        parent.endSheet(alert.window, returnCode: .alertThirdButtonReturn)
    }

    private func confirmClose() async -> NSApplication.ModalResponse {
        let alert = NSAlert()
        alert.messageText = String(localized: "Save the recording before closing?")
        alert.informativeText = String(localized: "If you don’t save, this recording will be discarded.")
        let recording: Bool
        switch state {
        case .starting, .recording: recording = true
        default: recording = false
        }
        alert.addButton(withTitle: recording ? String(localized: "Stop & Save") : String(localized: "Save…"))
        alert.addButton(withTitle: String(localized: "Don’t Save"))
        alert.addButton(withTitle: String(localized: "Cancel")).keyEquivalent = "\u{1b}"
        confirmationAlert = alert
        present()
        let response = await alert.beginSheetModal(for: activeWindow)
        confirmationAlert = nil
        return response
    }

    func prepareToClose() async -> Bool {
        guard !isClosing, !isSaving else { return false }
        isClosing = true
        defer { isClosing = false }
        switch state {
        case .selecting, .countdown, .failed, .preview(_, saved: .some):
            discard()
        case .discarding, .closed:
            break
        case .starting, .recording, .finishing, .preview:
            let decision = await confirmClose()
            switch decision {
            case .alertSecondButtonReturn: discard()
            case .alertFirstButtonReturn:
                stopWhenStarted = true
                stopRecording()
                await operation?.value
                if case .preview = state { present() }
                guard await saveResult() else { return false }
                discard()
            default:
                present()
                return false
            }
        }
        await operation?.value
        if case .closed = state { return true }
        return false
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        requestClose()
        return false
    }

    func requestClose() {
        Task { _ = await prepareToClose() }
    }

    private func finishDiscarding() async {
        let error = await cleanDirectory()
        finishClosing(cleanupError: error)
    }

    private func finishClosing(cleanupError: String?) {
        guard let cleanupError else {
            state = .closed
            window.orderOut(nil)
            window.contentView = nil
            window.close()
            closePreview()
            didClose()
            return
        }
        state = .failed(cleanupError)
        closePreview()
        present()
    }

    private func closePreview() {
        previewWindow?.contentView = nil
        previewWindow?.close()
        previewWindow = nil
        previewHasBeenSized = false
    }

    private func cleanDirectory() async -> String? {
        guard let directory else { return nil }
        do {
            try await RecordingFiles.removeSession(directory)
            self.directory = nil
            return nil
        } catch {
            return error.localizedDescription
        }
    }

}

private final class RecordingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
