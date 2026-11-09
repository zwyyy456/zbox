import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class RecordingSession: NSObject, NSWindowDelegate {
    enum State {
        case selecting(RecordingTargetKind?)
        case ready(RecordingTarget)
        case countdown(Int)
        case starting
        case recording(ContinuousClock.Instant)
        case finishing
        case converting(Double)
        case preview(URL, saved: URL?)
        case discarding
        case failed(String)
        case closed
    }

    enum CloseDecision { case save, discard, cancel }

    let kind: RecordingKind
    private(set) var state = State.selecting(nil)
    private(set) var status: String?
    private(set) var isClosing = false
    private(set) var isSaving = false
    var options: RecordingOptions {
        didSet { defaults.set(try? JSONEncoder().encode(options), forKey: optionsKey) }
    }

    @ObservationIgnored private let window: RecordingPanel
    @ObservationIgnored private let targetSelection = RecordingTargetSelection()
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let didClose: @MainActor () -> Void
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var recorder: ScreenRecorder?
    @ObservationIgnored private var gifDeadline: Task<Void, Never>?
    @ObservationIgnored private var directory: URL?
    @ObservationIgnored private var stopWhenStarted = false
    private var closeDecision: CheckedContinuation<CloseDecision, Never>?

    private var optionsKey: String { "plugin.screenshot.recording.\(kind.rawValue).options" }
    var isConfirmingClose: Bool { closeDecision != nil }

    var canStop: Bool {
        if case .recording = state { return true }
        return false
    }

    var blocksCapture: Bool {
        switch state {
        case .selecting, .ready, .countdown, .starting, .recording, .finishing, .discarding: true
        case .converting, .preview, .failed, .closed: false
        }
    }

    init(kind: RecordingKind, defaults: UserDefaults, didClose: @escaping @MainActor () -> Void) {
        self.kind = kind
        self.defaults = defaults
        self.didClose = didClose
        options = RecordingOptions(kind: kind, saved: defaults.data(forKey: "plugin.screenshot.recording.\(kind.rawValue).options"))
        window = RecordingPanel(contentRect: .zero, styleMask: [.titled, .closable, .nonactivatingPanel],
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
        resize(width: 440, height: 130, center: true)
    }

    func present() {
        if case .selecting(.some) = state { return }
        if case .closed = state { return }
        if let sheet = window.attachedSheet {
            sheet.makeKeyAndOrderFront(nil)
        } else {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    func showCaptureBlocked() {
        status = String(localized: "Finish or cancel the recording session before taking a screenshot.")
        if canStop { resize(width: 360, height: 145) }
        present()
    }

    func choose(_ target: RecordingTargetKind) {
        guard case .selecting(nil) = state else { return }
        status = nil
        state = .selecting(target)
        let windowID = CGWindowID(window.windowNumber)
        window.orderOut(nil)
        targetSelection.choose(target, excluding: windowID) { [weak self] result in
            guard let self, case .selecting(let selected) = state, selected == target else { return }
            switch result {
            case .success(let target?):
                prepare(target)
            case .success(nil):
                chooseAgain()
            case .failure(let error):
                chooseAgain()
                status = error.localizedDescription
                resize(width: 440, height: 190)
            }
            present()
        }
    }

    func prepare(_ target: RecordingTarget) {
        guard case .selecting = state else { return }
        state = .ready(target)
        resize(width: 460, height: 355)
    }

    func chooseAgain() {
        targetSelection.cancel()
        status = nil
        state = .selecting(nil)
        resize(width: 440, height: 130)
    }

    func start() {
        guard case .ready(let target) = state, operation == nil else { return }
        let options = options
        status = nil
        state = .countdown(3)
        resize(width: 360, height: 118)
        operation = Task {
            defer { operation = nil }
            do {
                try Task.checkCancellation()
                for seconds in (1...3).reversed() {
                    state = .countdown(seconds)
                    try await Task.sleep(for: .seconds(1))
                    try Task.checkCancellation()
                }
                state = .starting
                setControlChrome(true)
                positionControls()
                let filter = try await target.captureFilter(excluding: CGWindowID(window.windowNumber))
                try Task.checkCancellation()

                let directory = try await RecordingFiles.makeSessionDirectory()
                self.directory = directory
                try Task.checkCancellation()
                let video = directory.appending(path: "Recording.mp4")
                let recorder = try ScreenRecorder(target: target, filter: filter, options: options, url: video)
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
                try await RecordingFiles.validateVideo(video, size: options.outputSize(for: target.pixelSize))
                try Task.checkCancellation()

                let result: URL
                if kind == .gif {
                    let gif = directory.appending(path: "Recording.gif")
                    state = .converting(0)
                    try await GIFExporter.export(video: video, to: gif, frameRate: options.frameRate) { [weak self] progress in
                        await self?.updateProgress(progress)
                    }
                    result = gif
                } else {
                    result = video
                }
                try Task.checkCancellation()
                status = nil
                state = .preview(result, saved: nil)
                setControlChrome(false)
                resize(width: 660, height: 470, center: true)
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
                        decideClose(.cancel)
                        setControlChrome(false)
                        resize(width: 440, height: 160, center: true)
                        present()
                    }
                }
            }
        }
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
        status = nil
        gifDeadline?.cancel()
        targetSelection.cancel()
        if let operation {
            if let recorder { recorder.requestStop() }
            else { operation.cancel() }
        } else {
            operation = Task {
                await finishDiscarding()
                operation = nil
            }
        }
    }

    private func updateProgress(_ progress: Double) {
        guard case .converting = state else { return }
        state = .converting(progress)
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
        guard await panel.beginSheetModal(for: window) == .OK, let destination = panel.url else { return false }
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

    func decideClose(_ decision: CloseDecision) {
        guard let continuation = closeDecision else { return }
        closeDecision = nil
        continuation.resume(returning: decision)
    }

    func prepareToClose() async -> Bool {
        guard !isClosing, !isSaving else { return false }
        isClosing = true
        defer { isClosing = false }
        switch state {
        case .selecting, .ready, .countdown, .failed, .preview(_, saved: .some):
            discard()
        case .discarding, .closed:
            break
        case .starting, .recording, .finishing, .converting, .preview:
            let decision = await withCheckedContinuation { continuation in
                closeDecision = continuation
                present()
            }
            switch decision {
            case .cancel: return false
            case .discard: discard()
            case .save:
                stopWhenStarted = true
                stopRecording()
                await operation?.value
                guard await saveResult() else { return false }
                discard()
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
            didClose()
            return
        }
        state = .failed(cleanupError)
        setControlChrome(false)
        resize(width: 440, height: 160, center: true)
        present()
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

    private func setControlChrome(_ isControl: Bool) {
        window.titleVisibility = isControl ? .hidden : .visible
        window.titlebarAppearsTransparent = isControl
        window.standardWindowButton(.closeButton)?.isHidden = isControl
    }

    private func positionControls() {
        guard let frame = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
        window.setFrameTopLeftPoint(CGPoint(x: frame.maxX - window.frame.width - 16, y: frame.maxY - 16))
    }

    private func resize(width: CGFloat, height: CGFloat, center: Bool = false) {
        let screen = window.screen ?? NSScreen.main
        let available = screen?.visibleFrame.size ?? CGSize(width: width, height: height)
        window.setContentSize(CGSize(width: min(width, available.width), height: min(height, available.height - 36)))
        if center { window.center() }
    }
}

private final class RecordingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
