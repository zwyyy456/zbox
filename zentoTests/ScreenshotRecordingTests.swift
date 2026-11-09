import AVFoundation
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import ImageIO
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
        #expect(video.outputSize(for: pixels) == CGSize(width: 1001, height: 601))
        video.scale = 75
        #expect(video.outputSize(for: pixels) == CGSize(width: 751, height: 451))

        let gif = RecordingOptions(kind: .gif, saved: nil)
        #expect(gif.frameRate == 10)
        #expect(gif.showsCursor && !gif.capturesAudio)
        #expect(gif.outputSize(for: pixels) == pixels)
    }

    @MainActor
    @Test func discardWinsBeforeCountdownTaskRuns() async {
        var closeCount = 0
        let suite = "ScreenshotRecordingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = RecordingSession(kind: .gif, defaults: defaults) { closeCount += 1 }
        session.prepare(RecordingTarget(kind: .region, name: "Test Area", pixelSize: CGSize(width: 64, height: 48),
                                        source: .display(1, sourceRect: nil, displayFrame: .zero, scale: 1)))
        session.start()
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

    @Test func gifUsesSelectedCadenceAndCapsPlaybackAtThirtySeconds() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let video = folder.appending(path: "Input.mp4")
        let gif = folder.appending(path: "Result.gif")
        let size = CGSize(width: 64, height: 48)
        try await makeVideo(at: video, size: size)
        try await RecordingFiles.validateVideo(video, size: size)
        let asset = AVURLAsset(url: video)
        #expect(try await asset.load(.duration).seconds > 30)
        #expect(try await asset.loadTracks(withMediaType: .audio).isEmpty)

        try await GIFExporter.export(video: video, to: gif, frameRate: 15) { _ in }
        let result = try #require(CGImageSourceCreateWithURL(gif as CFURL, nil))
        #expect(CGImageSourceGetCount(result) == 450)
        let properties = try #require(CGImageSourceCopyProperties(result, nil) as? [CFString: Any])
        let loop = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        #expect(loop?[kCGImagePropertyGIFLoopCount] as? Int == 0)

        var playbackTime = 0.0
        for index in 0..<CGImageSourceGetCount(result) {
            let frame = try #require(CGImageSourceCopyPropertiesAtIndex(result, index, nil) as? [CFString: Any])
            #expect(frame[kCGImagePropertyPixelWidth] as? Int == Int(size.width))
            #expect(frame[kCGImagePropertyPixelHeight] as? Int == Int(size.height))
            let metadata = frame[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            playbackTime += try #require(metadata?[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
        }
        #expect(abs(playbackTime - 30) < 0.0001)
        let first = try #require(CGImageSourceCreateImageAtIndex(result, 0, nil))
        let last = try #require(CGImageSourceCreateImageAtIndex(result, 449, nil))
        #expect(first.dataProvider?.data != last.dataProvider?.data)

        let cancelledGIF = folder.appending(path: "Cancelled.gif")
        let (progress, progressSignal) = AsyncStream.makeStream(of: Void.self)
        let export = Task {
            defer { progressSignal.finish() }
            try await GIFExporter.export(video: video, to: cancelledGIF, frameRate: 15) { _ in
                progressSignal.yield(())
                // Hold at the first progress update so cancellation wins deterministically.
                try? await Task.sleep(for: .seconds(5))
            }
        }
        for await _ in progress { break }
        export.cancel()
        await #expect(throws: CancellationError.self) { try await export.value }
    }

    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        return folder
    }

    private func makeVideo(at url: URL, size: CGSize) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
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
