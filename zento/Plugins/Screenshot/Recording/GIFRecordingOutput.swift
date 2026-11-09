import CoreMedia
import CoreVideo
import ScreenCaptureKit
import Synchronization
import VideoToolbox

// ScreenCaptureKit invokes this output on a serial queue. The mutex also protects
// finalization after stopCapture; cancellation uses a separate atomic to interrupt encoding.
nonisolated final class GIFRecordingOutput: NSObject, SCStreamOutput, Sendable {
    private struct State {
        var encoder: GIFEncoder?
        var firstTime: CMTime?
        var startedAt: ContinuousClock.Instant?
        var error: Error?
        var finished = false
    }

    private let state: Mutex<State>
    private let cancelled = Atomic(false)
    private let events: AsyncStream<RecordingEvents.Event>.Continuation
    let queue = DispatchQueue(label: "tech.hyperseek.zento.gif-encoding", qos: .userInitiated)

    init(url: URL, size: CGSize, frameRate: Int, events: AsyncStream<RecordingEvents.Event>.Continuation) throws {
        self.events = events
        state = Mutex(State(encoder: try GIFEncoder(url: url, size: size, frameRate: frameRate)))
    }

    func cancel() {
        cancelled.store(true, ordering: .relaxed)
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let status = attachments.first?[.status] as? Int, status == SCFrameStatus.complete.rawValue,
              let pixels = sampleBuffer.imageBuffer else { return }
        let time = sampleBuffer.presentationTimeStamp
        var image: CGImage?
        let result = VTCreateCGImageFromCVPixelBuffer(pixels, options: nil, imageOut: &image)
        state.withLock { state in
            guard !state.finished, state.error == nil, !cancelled.load(ordering: .relaxed) else { return }
            do {
                guard result == noErr, let image else { throw RecordingError.gifEncoding }
                let first = state.firstTime ?? time
                try state.encoder?.append(image, at: max(0, (time - first).seconds)) {
                    self.cancelled.load(ordering: .relaxed)
                }
                if state.firstTime == nil {
                    state.firstTime = time
                    state.startedAt = .now
                    events.yield(.started)
                }
            } catch {
                state.error = error
                events.yield(.failed(error))
            }
        }
    }

    func finish(at end: ContinuousClock.Instant) async throws {
        // Enqueue after stopCapture so already-delivered frames are processed before the trailer.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    try self.state.withLock { state in
                        guard !state.finished else { return }
                        defer {
                            state.finished = true
                            state.encoder = nil
                        }
                        if self.cancelled.load(ordering: .relaxed) { throw CancellationError() }
                        if let error = state.error { throw error }
                        guard let startedAt = state.startedAt else { throw RecordingError.emptyVideo }
                        let duration = startedAt.duration(to: end)
                        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
                        try state.encoder?.finish(at: seconds) { self.cancelled.load(ordering: .relaxed) }
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
