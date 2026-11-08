import AppKit
import Observation
import ScreenCaptureKit
import SwiftUI
import OSLog

@MainActor @Observable
final class ScreenshotScrollSession {
    private let logger = Logger(subsystem: "tech.hyperseek.zento", category: "ScreenshotScroll")
    private(set) var preview: CGImage?
    private(set) var height = 0
    private(set) var message = String(localized: "Scroll slowly downward. Keep fixed headers and footers outside the selection.")
    private(set) var paused = false
    private(set) var finishing = false
    private(set) var canResume = true
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var captureTask: Task<Void, Never>?
    @ObservationIgnored private var panel: NSPanel?
    @ObservationIgnored private var border: NSPanel?
    @ObservationIgnored private var stitcher = ScreenshotScrollStitcher()
    private let content: SCShareableContent
    private let screen: NSScreen
    private let screenFrame: CGRect
    private let screenScale: CGFloat
    private let area: CGRect
    private let completed: (CGImage) -> Void
    private let cancelled: () -> Void
    private var active = true

    init(content: SCShareableContent, screen: NSScreen, area: CGRect,
         completed: @escaping (CGImage) -> Void, cancelled: @escaping () -> Void) {
        self.content = content; self.screen = screen; self.area = area
        screenFrame = screen.frame
        screenScale = screen.backingScaleFactor
        self.completed = completed; self.cancelled = cancelled
    }

    func start() {
        let border = NSPanel(contentRect: area.insetBy(dx: -2, dy: -2),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        border.hasShadow = false
        border.isOpaque = false; border.backgroundColor = .clear; border.ignoresMouseEvents = true
        border.level = .screenSaver; border.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        border.isReleasedWhenClosed = false
        let view = NSView(frame: CGRect(origin: .zero, size: border.frame.size))
        view.wantsLayer = true; view.layer?.borderWidth = 2; view.layer?.borderColor = NSColor.systemGreen.cgColor
        border.contentView = view; border.orderFrontRegardless(); self.border = border
        let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 280, height: 440),
            styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = String(localized: "Scrolling Screenshot")
        panel.level = .screenSaver; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: ScreenshotScrollView(session: self))
        let visible = screen.visibleFrame
        let x = area.maxX + 12 + 280 <= visible.maxX ? area.maxX + 12 : max(visible.minX, area.minX - 292)
        panel.setFrameOrigin(CGPoint(x: x, y: max(visible.minY, min(area.maxY - 440, visible.maxY - 470))))
        logger.info("Started: selectionSize=\(self.area.width)x\(self.area.height), scale=\(self.screenScale), previewOverlapsSelection=\(panel.frame.intersects(self.area))")
        panel.orderFrontRegardless(); self.panel = panel
        resume()
    }

    func resume() {
        guard active, !finishing, canResume else { return }
        logger.info("Resume: acceptedHeight=\(self.height)")
        paused = false
        message = String(localized: "Scroll slowly downward. Keep fixed headers and footers outside the selection.")
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let pixelWidth = Int((area.width * screenScale).rounded())
                let pixelHeight = Int((area.height * screenScale).rounded())
                guard pixelWidth >= 64, pixelHeight >= 64,
                      pixelWidth * pixelHeight <= 16_000_000 else { throw ScreenshotScrollStitcher.Failure.dimensions }
                let frames = AsyncThrowingStream<(image: CGImage, capturedAt: ContinuousClock.Instant), Error>.makeStream(bufferingPolicy: .bufferingOldest(2))
                let producer = Task { @MainActor in
                    do {
                        let clock = ContinuousClock()
                        var previousCapture: ContinuousClock.Instant?
                        while !Task.isCancelled {
                            let started = clock.now
                            guard NSScreen.screens.contains(screen), screen.frame == screenFrame,
                                  screen.backingScaleFactor == screenScale, CGPreflightScreenCaptureAccess() else {
                                throw ScreenshotError.unavailable
                            }
                            let image = try await ScreenshotCapture.image(content: content, screen: screen, area: area, alignToPixels: true)
                            try Task.checkCancellation()
                            let capturedAt = clock.now
                            if let previousCapture {
                                logger.info("Capture interval=\(String(describing: previousCapture.duration(to: capturedAt)), privacy: .public), duration=\(String(describing: started.duration(to: capturedAt)), privacy: .public)")
                            }
                            previousCapture = capturedAt
                            switch frames.continuation.yield((image, capturedAt)) {
                            case .dropped: throw CaptureFailure.backlog
                            case .terminated: return
                            case .enqueued(let remaining): logger.debug("Queued frames=\(2 - remaining)")
                            @unknown default: return
                            }
                            try await clock.sleep(until: started.advanced(by: .milliseconds(100)))
                        }
                        frames.continuation.finish()
                    } catch is CancellationError { frames.continuation.finish() }
                    catch { frames.continuation.finish(throwing: error) }
                }
                captureTask = producer
                defer { producer.cancel(); captureTask = nil }
                for try await frame in frames.stream {
                    try Task.checkCancellation()
                    let started = ContinuousClock.now
                    let update = try await stitcher.append(frame.image, capturedAt: frame.capturedAt)
                    logger.info("Matching duration=\(String(describing: started.duration(to: .now)), privacy: .public)")
                    guard active, !Task.isCancelled else { return }
                    if let update { preview = update.preview; height = update.height }
                }
            } catch {
                guard active, !Task.isCancelled else { return }
                logger.error("Paused: acceptedHeight=\(self.height), errorType=\(String(reflecting: type(of: error)), privacy: .public), code=\((error as NSError).code)")
                paused = true
                switch error {
                case ScreenshotScrollStitcher.Failure.alignment:
                    message = String(localized: "Alignment lost. Scroll back to the last preview, then retry; or finish with the captured content.")
                case CaptureFailure.backlog:
                    message = String(localized: "Capture processing could not keep up. Finish with the captured content or retry.")
                case ScreenshotScrollStitcher.Failure.dimensions:
                    canResume = false
                    message = String(localized: "Choose an area at least 64 pixels wide and high, up to 16 million pixels. Cancel and select a new area.")
                case ScreenshotScrollStitcher.Failure.limit:
                    canResume = false
                    message = String(localized: "The long-image limit was reached. Finish with the captured content.")
                default:
                    canResume = false
                    message = String(localized: "Capture stopped. The display, permission, or selection is unavailable. You can finish with the captured content.")
                }
            }
        }
    }

    private enum CaptureFailure: Error { case backlog }

    func finish() {
        guard active, height > 0, !finishing else { return }
        logger.info("Finishing: acceptedHeight=\(self.height)")
        finishing = true
        captureTask?.cancel()
        let pending = task
        task = Task { [weak self] in
            await pending?.value
            guard let self, active, !Task.isCancelled else { return }
            do {
                let image = try await stitcher.finish()
                guard active, !Task.isCancelled else { return }
                close()
                completed(image)
            } catch {
                guard active, !Task.isCancelled else { return }
                finishing = false; paused = true; canResume = false
                message = String(localized: "The long image could not be assembled. Try finishing again or cancel.")
            }
        }
    }

    func cancel() { logger.info("Cancelled"); close(); cancelled() }

    func close() {
        active = false
        captureTask?.cancel(); captureTask = nil
        task?.cancel(); task = nil
        panel?.orderOut(nil); panel?.contentView = nil; panel?.close(); panel = nil
        border?.orderOut(nil); border?.close(); border = nil
        preview = nil
        // An in-flight actor call owns its old state only until it observes cancellation.
        stitcher = ScreenshotScrollStitcher()
    }
}

private struct ScreenshotScrollView: View {
    let session: ScreenshotScrollSession
    var body: some View {
        VStack(spacing: 10) {
            Text(session.message).font(.callout).fixedSize(horizontal: false, vertical: true)
            if let image = session.preview {
                Image(image, scale: 1, label: Text("Stitched screenshot preview")).resizable().scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Text("\(session.height) captured rows")
                    .font(.caption).foregroundStyle(.secondary)
            } else if !session.paused { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            else { Spacer() }
            HStack {
                Button("Cancel") { session.cancel() }.keyboardShortcut(.cancelAction)
                if session.paused && session.canResume {
                    Button("Retry") { session.resume() }.disabled(session.finishing)
                }
                Button("Finish") { session.finish() }
                    .disabled(session.height == 0 || session.finishing)
            }
        }.padding(12).frame(width: 280, height: 440)
    }
}
