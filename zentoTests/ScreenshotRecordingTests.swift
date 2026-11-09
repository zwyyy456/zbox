import AVFoundation
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import ImageIO
import ScreenCaptureKit
import Testing
@testable import zento

struct ScreenshotRecordingTests {
    @Test func regionPixelsAndRecordingDefaults() {
        let display = CGRect(x: -1440, y: 100, width: 1440, height: 900)
        let selection = CGRect(x: -1359.75, y: 200.2, width: 501, height: 301)
        let region = ScreenshotGeometry.pixelAligned(ScreenshotGeometry.sourceRect(selection, in: display), scale: 2)
        #expect(region == CGRect(x: 80.5, y: 499, width: 500.5, height: 300.5))
        let pixels = CGSize(width: region.width * 2, height: region.height * 2)

        var video = RecordingOptions(kind: .video, saved: nil)
        #expect(video.frameRate == 60)
        #expect(video.showsCursor && !video.capturesAudio)
        #expect(video.outputSize(for: pixels, kind: .video) == CGSize(width: 1000, height: 600))
        video.scale = 75
        #expect(video.outputSize(for: pixels, kind: .video) == CGSize(width: 750, height: 450))

        let gif = RecordingOptions(kind: .gif, saved: nil)
        #expect(gif.frameRate == 10)
        #expect(gif.showsCursor && !gif.capturesAudio)
        #expect(gif.outputSize(for: pixels, kind: .gif) == pixels)
    }

    @MainActor
    @Test func preparationAllowsScreenshotsAndSelectionStartsCountdown() async {
        let suite = "ScreenshotRecordingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        @MainActor final class CaptureState { var isAvailable = false }
        let capture = CaptureState()
        let session = RecordingSession(kind: .video, defaults: defaults,
                                       canBeginCapture: { capture.isAvailable }, didClose: {})
        #expect(!session.blocksCapture)
        session.choose(.region)
        guard case .selecting(nil) = session.state else {
            Issue.record("Target selection started while a screenshot was active")
            return
        }
        #expect(session.status != nil)
        capture.isAvailable = true
        session.startRecording(RecordingTarget(kind: .region, name: "Test Area", pixelSize: CGSize(width: 64, height: 48),
                                        source: .display(1, sourceRect: nil, displayFrame: .zero, scale: 1)))
        guard case .countdown(3) = session.state else {
            Issue.record("Selecting a target should start the countdown without another confirmation")
            return
        }
        #expect(session.blocksCapture)
        session.discard()
        #expect(await session.prepareToClose())
    }

    @MainActor
    @Test func discardWinsBeforeCountdownTaskRuns() async {
        var closeCount = 0
        let suite = "ScreenshotRecordingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = RecordingSession(kind: .gif, defaults: defaults, canBeginCapture: { true }) { closeCount += 1 }
        session.startRecording(RecordingTarget(kind: .region, name: "Test Area", pixelSize: CGSize(width: 64, height: 48),
                                        source: .display(1, sourceRect: nil, displayFrame: .zero, scale: 1)))
        session.discard()
        session.stopRecording()
        #expect(await session.prepareToClose())
        #expect(closeCount == 1)
        guard case .closed = session.state else {
            Issue.record("Discarded recording reentered the countdown or capture state")
            return
        }
        #expect(!session.blocksCapture)
    }

    @MainActor
    @Test func gifStartDelayPersistsAndCanBeSkippedOrCancelled() async throws {
        let suite = "ScreenshotRecordingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        // Existing saved preferences have no delay field and retain their other options.
        let legacy = Data(#"{"frameRate":15,"scale":75,"showsCursor":false,"capturesAudio":false}"#.utf8)
        let oldOptions = RecordingOptions(kind: .gif, saved: legacy)
        #expect(oldOptions.selectedStartDelay == .threeSeconds)
        #expect(oldOptions.frameRate == 15 && oldOptions.scale == 75 && !oldOptions.showsCursor)
        let target = RecordingTarget(kind: .region, name: "Test Area", pixelSize: CGSize(width: 64, height: 48),
                                     source: .display(1, sourceRect: nil, displayFrame: .zero, scale: 1))
        let waiting = RecordingSession(kind: .gif, defaults: defaults, canBeginCapture: { true }, didClose: {})
        waiting.startRecording(target)
        try await Task.sleep(for: .milliseconds(50))
        waiting.startImmediately()
        guard case .starting = waiting.state else { Issue.record("Start Now did not leave countdown"); return }
        #expect(waiting.options.selectedStartDelay == .threeSeconds)
        waiting.startImmediately() // Repeated actions must not start another operation.
        waiting.discard()
        #expect(await waiting.prepareToClose())
        guard case .closed = waiting.state else { Issue.record("Cancellation did not win over Start Now"); return }

        let configured = RecordingSession(kind: .gif, defaults: defaults, canBeginCapture: { true }, didClose: {})
        configured.options.selectedStartDelay = .immediately
        let immediate = RecordingSession(kind: .gif, defaults: defaults, canBeginCapture: { true }, didClose: {})
        #expect(immediate.options.selectedStartDelay == .immediately)
        immediate.startRecording(target)
        guard case .starting = immediate.state else { Issue.record("Immediate preference still entered countdown"); return }
        immediate.discard()
        #expect(await immediate.prepareToClose())
        #expect(RecordingOptions(kind: .video, saved: defaults.data(forKey: RecordingKind.video.optionsKey)).selectedStartDelay == .threeSeconds)
        configured.discard()
        #expect(await configured.prepareToClose())
    }

    @Test func failedSavePreservesTemporaryResultAndDestination() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appending(path: "Recording.mp4")
        let destination = folder.appending(path: "Saved.mp4")
        let recorded = Data([1, 2, 3])
        let existing = Data([4, 5, 6])
        try recorded.write(to: source)
        try existing.write(to: destination)
        await #expect(throws: (any Error).self) {
            try await RecordingFiles.save(source, to: destination, replaceExisting: false)
        }
        #expect(try Data(contentsOf: source) == recorded)
        #expect(try Data(contentsOf: destination) == existing)

        try await RecordingFiles.save(source, to: destination, replaceExisting: true)
        #expect(try Data(contentsOf: destination) == recorded)
        #expect(try Data(contentsOf: source) == recorded)

        let newFile = folder.appending(path: "New.mp4")
        try await RecordingFiles.save(source, to: newFile, replaceExisting: false)
        #expect(try Data(contentsOf: newFile) == recorded)
    }

    @Test func gifPreservesOddDimensionsTimingAndLoopWithoutVideo() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let size = CGSize(width: 65, height: 49)
        let first = try makeImage(size: size, shade: 0.1)
        let last = try makeImage(size: size, shade: 0.9)
        for rate in [10, 15, 20] {
            let url = folder.appending(path: "direct-\(rate).gif")
            let encoder = try GIFEncoder(url: url, size: size, frameRate: rate)
            try encoder.append(first, at: 0, isCancelled: { false })
            try encoder.append(last, at: 1, isCancelled: { false })
            try encoder.finish(at: 31, isCancelled: { false })
            let result = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
            #expect(CGImageSourceGetCount(result) == 30 * rate)
            let properties = try #require(CGImageSourceCopyProperties(result, nil) as? [CFString: Any])
            let loop = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            #expect(loop?[kCGImagePropertyGIFLoopCount] as? Int == 0)
            var duration = 0.0
            for index in 0..<CGImageSourceGetCount(result) {
                let frame = try #require(CGImageSourceCopyPropertiesAtIndex(result, index, nil) as? [CFString: Any])
                #expect(frame[kCGImagePropertyPixelWidth] as? Int == 65)
                #expect(frame[kCGImagePropertyPixelHeight] as? Int == 49)
                let gif = frame[kCGImagePropertyGIFDictionary] as? [CFString: Any]
                duration += try #require(gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
            }
            #expect(abs(duration - 30) < 0.0001)
            let beginning = try #require(CGImageSourceCreateImageAtIndex(result, 0, nil))
            let ending = try #require(CGImageSourceCreateImageAtIndex(result, 30 * rate - 1, nil))
            #expect(beginning.dataProvider?.data != ending.dataProvider?.data)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).allSatisfy { $0.hasSuffix(".gif") })
    }

    @Test func gifCancellationAndEmptyRecordingDoNotFinalize() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let size = CGSize(width: 65, height: 49)
        let url = folder.appending(path: "cancelled.gif")
        let encoder = try GIFEncoder(url: url, size: size, frameRate: 15)
        try encoder.append(makeImage(size: size, shade: 0.5), at: 0, isCancelled: { false })
        #expect(throws: CancellationError.self) {
            try encoder.finish(at: 30, isCancelled: { true })
        }
        #expect(try Data(contentsOf: url).isEmpty)
        let empty = try GIFEncoder(url: folder.appending(path: "empty.gif"), size: size, frameRate: 15)
        #expect(throws: RecordingError.self) {
            try empty.finish(at: 1, isCancelled: { false })
        }
    }

    @Test func gifOutputCancellationFinishesWithoutFrames() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (_, events) = AsyncStream.makeStream(of: RecordingEvents.Event.self)
        let output = try GIFRecordingOutput(url: folder.appending(path: "cancelled.gif"),
                                            size: CGSize(width: 65, height: 49), frameRate: 15, events: events)
        output.cancel()
        await #expect(throws: CancellationError.self) { try await output.finish(at: .now) }
    }

    @Test func videoCodecsUseAlignedSizeAndPersistChoice() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let odd = CGSize(width: 1001, height: 601)
        var options = RecordingOptions(kind: .video, saved: nil)
        #expect(options.selectedVideoCodec == .hevc)
        for codec in RecordingVideoCodec.allCases {
            options.selectedVideoCodec = codec
            let saved = try JSONEncoder().encode(options)
            #expect(RecordingOptions(kind: .video, saved: saved).selectedVideoCodec == codec)
            let size = options.outputSize(for: odd, kind: .video)
            #expect(size == CGSize(width: 1000, height: 600))
            let url = folder.appending(path: "\(codec.rawValue).mp4")
            try await makeVideo(at: url, size: size, codec: codec.avCodec)
            try await RecordingFiles.validateVideo(url, size: size)
            let asset = AVURLAsset(url: url)
            let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
            let format = try #require(try await track.load(.formatDescriptions).first)
            #expect(CMFormatDescriptionGetMediaSubType(format) == (codec == .hevc ? kCMVideoCodecType_HEVC : kCMVideoCodecType_H264))
        }
    }

    @Test func previewUsesCapturePointsWithoutUpscalingAndFitsAvailableScreen() {
        let natural = RecordingPreviewLayout.naturalSize(pixels: CGSize(width: 800, height: 500), captureScale: 2)
        #expect(natural == CGSize(width: 400, height: 250))
        let footer = CGSize(width: 320, height: 52)
        let available = CGSize(width: 1000, height: 700)
        #expect(RecordingPreviewLayout.initialContentSize(natural: natural, footer: footer, available: available)
                == CGSize(width: 400, height: 302))
        let tiny = CGSize(width: 100, height: 60)
        #expect(RecordingPreviewLayout.initialContentSize(natural: tiny, footer: footer, available: available)
                == CGSize(width: 100, height: 112))
        #expect(RecordingPreviewLayout.fittedImageSize(natural: tiny, available: CGSize(width: 320, height: 60)) == tiny)
        let short = CGSize(width: 200, height: 10)
        #expect(RecordingPreviewLayout.initialContentSize(natural: short, footer: footer, available: available)
                == CGSize(width: 200, height: 62))
        let large = CGSize(width: 2000, height: 1000)
        #expect(RecordingPreviewLayout.initialContentSize(natural: large, footer: footer, available: available)
                == CGSize(width: 1000, height: 552))
    }

    private func makeImage(size: CGSize, shade: CGFloat) throws -> CGImage {
        let context = try #require(CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: shade, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        return try #require(context.makeImage())
    }

    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        return folder
    }

    private func makeVideo(at url: URL, size: CGSize, codec: AVVideoCodecType = .h264) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height)
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height)
        ])
        writer.add(input)
        try #require(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        let pool = try #require(adaptor.pixelBufferPool)
        for (time, shade) in [(0, 32), (1, 92), (29, 155), (31, 230)] {
            var buffer: CVPixelBuffer?
            try #require(CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess)
            let pixels = try #require(buffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            if let data = CVPixelBufferGetBaseAddress(pixels) {
                memset(data, Int32(shade), CVPixelBufferGetBytesPerRow(pixels) * CVPixelBufferGetHeight(pixels))
            }
            CVPixelBufferUnlockBaseAddress(pixels, [])
            let deadline = ContinuousClock.now + .seconds(5)
            while !input.isReadyForMoreMediaData && writer.status == .writing && ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(5))
            }
            try #require(input.isReadyForMoreMediaData)
            try #require(adaptor.append(pixels, withPresentationTime: CMTime(value: Int64(time), timescale: 1)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        try #require(writer.status == .completed)
    }
}
