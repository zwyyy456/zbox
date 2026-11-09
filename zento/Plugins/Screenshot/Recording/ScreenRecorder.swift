import AVFoundation
import CoreMedia
import ScreenCaptureKit

@MainActor
final class ScreenRecorder {
    private let stream: SCStream
    private let output: SCRecordingOutput
    private let delegate: RecordingEvents
    private let events: AsyncStream<RecordingEvents.Event>
    private var streamStarted = false
    private var stopRequested = false
    private var stopTask: Task<Void, Never>?

    init(target: RecordingTarget, filter: SCContentFilter, options: RecordingOptions, url: URL) throws {
        let config = SCStreamConfiguration()
        let size = options.outputSize(for: target.pixelSize)
        config.width = Int(size.width)
        config.height = Int(size.height)
        config.minimumFrameInterval = CMTime(value: 1, timescale: Int32(options.frameRate))
        config.showsCursor = options.showsCursor
        config.capturesAudio = options.capturesAudio
        config.captureDynamicRange = .SDR
        config.captureResolution = .best
        config.ignoreShadowsSingleWindow = true
        config.preservesAspectRatio = true
        config.scalesToFit = false
        if let source = target.sourceRect { config.sourceRect = source }

        let (events, continuation) = AsyncStream.makeStream(of: RecordingEvents.Event.self)
        let delegate = RecordingEvents(continuation: continuation)
        self.events = events
        self.delegate = delegate
        stream = SCStream(filter: filter, configuration: config, delegate: delegate)
        let recording = SCRecordingOutputConfiguration()
        recording.outputURL = url
        recording.outputFileType = .mp4
        recording.videoCodecType = .h264
        output = SCRecordingOutput(configuration: recording, delegate: delegate)
        try stream.addRecordingOutput(output)
    }

    func record(started: () -> Void, stoppedBySystemMenu: () -> Void) async throws {
        defer { delegate.continuation.finish() }
        try await stream.startCapture()
        streamStarted = true
        if stopRequested { requestStop() }

        for await event in events {
            switch event {
            case .started:
                started()
            case .stoppedByUser:
                streamStarted = false
                stoppedBySystemMenu()
            case .finished:
                requestStop()
                await stopTask?.value
                return
            case .failed(let error):
                requestStop()
                await stopTask?.value
                throw error
            }
        }
        requestStop()
        await stopTask?.value
        throw CancellationError()
    }

    func requestStop() {
        stopRequested = true
        guard streamStarted, stopTask == nil else { return }
        stopTask = Task {
            do {
                try await stream.stopCapture()
            } catch {
                if streamStarted { delegate.continuation.yield(.failed(error)) }
            }
        }
    }
}

private nonisolated final class RecordingEvents: NSObject, SCStreamDelegate, SCRecordingOutputDelegate {
    enum Event: Sendable {
        case started, stoppedByUser, finished, failed(Error)
    }

    let continuation: AsyncStream<Event>.Continuation

    init(continuation: AsyncStream<Event>.Continuation) {
        self.continuation = continuation
    }

    func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        continuation.yield(.started)
    }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        continuation.yield(.finished)
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        continuation.yield(.failed(error))
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        if (error as? SCStreamError)?.code == .userStopped {
            continuation.yield(.stoppedByUser)
        } else {
            continuation.yield(.failed(error))
        }
    }
}
