import AVFoundation
import CoreMedia
import CoreVideo
import ImageIO
import UniformTypeIdentifiers
import VideoToolbox

nonisolated enum GIFExporter {
    @concurrent static func export(video: URL, to gif: URL, frameRate: Int,
                                   progress: @Sendable (Double) async -> Void) async throws {
        let asset = AVURLAsset(url: video)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw RecordingError.emptyVideo
        }
        let timeRange = try await track.load(.timeRange)
        let duration = min(timeRange.duration.seconds, Double(RecordingOptions.gifLimit))
        guard duration.isFinite, duration > 0 else { throw RecordingError.emptyVideo }

        // GIF delay is stored in centiseconds. Round each boundary so 15 fps does not drift.
        // Common GIF players treat a 0 or 1 centisecond delay as 100 ms.
        let end = max(2, Int((duration * 100).rounded(.down)))
        let starts = (0..<(RecordingOptions.gifLimit * frameRate)).map {
            ($0 * 100 + frameRate / 2) / frameRate
        }.prefix { $0 <= end - 2 }
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(start: timeRange.start,
                                       duration: CMTimeMinimum(timeRange.duration, CMTime(value: Int64(RecordingOptions.gifLimit), timescale: 1)))
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? RecordingError.emptyVideo }
        defer { reader.cancelReading() }

        guard FileManager.default.createFile(atPath: gif.path, contents: nil) else {
            throw RecordingError.gifEncoding
        }
        let file = try FileHandle(forWritingTo: gif)
        defer { try? file.close() }

        guard var current = output.copyNextSampleBuffer() else { throw reader.error ?? RecordingError.emptyVideo }
        var next = output.copyNextSampleBuffer()
        var image: CGImage?
        for index in starts.indices {
            try Task.checkCancellation()
            // Sample at the center of the requested frame slot, independently of
            // the rounded GIF delays, so small capture jitter doesn't skip frames.
            let timestamp = timeRange.start + CMTime(value: Int64(index * 2 + 1), timescale: Int32(frameRate * 2))
            while let sample = next, sample.presentationTimeStamp <= timestamp {
                try Task.checkCancellation()
                current = sample
                image = nil
                next = output.copyNextSampleBuffer()
            }
            if reader.status == .failed { throw reader.error ?? RecordingError.emptyVideo }
            let nextStart = index + 1 < starts.endIndex ? starts[index + 1] : end
            let delay = Double(nextStart - starts[index]) / 100
            try autoreleasepool {
                if image == nil, let pixels = current.imageBuffer {
                    let status = VTCreateCGImageFromCVPixelBuffer(pixels, options: nil, imageOut: &image)
                    guard status == noErr else { throw RecordingError.gifEncoding }
                }
                guard let image else { throw RecordingError.gifEncoding }
                try writeFrame(image, delay: delay, first: index == starts.startIndex, to: file)
            }
            if index.isMultiple(of: frameRate) { await progress(Double(index) / Double(starts.count)) }
        }
        try Task.checkCancellation()
        try file.write(contentsOf: Data([0x3b])) // GIF trailer
        try file.close()
        await progress(1)
    }

    private static func writeFrame(_ image: CGImage, delay: Double, first: Bool, to file: FileHandle) throws {
        // Image I/O retains a multi-image destination's frames until finalization.
        // Encode one GIF at a time and stream its blocks into the animation.
        let buffer = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(buffer, UTType.gif.identifier as CFString, 1, nil) else {
            throw RecordingError.gifEncoding
        }
        if first {
            CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        }
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyGIFDictionary: [
            kCGImagePropertyGIFUnclampedDelayTime: delay
        ]] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw RecordingError.gifEncoding }
        try Task.checkCancellation()

        let bytes = buffer as Data
        let logicalScreenEnd = 13
        let packedFields = 10
        guard bytes.count > logicalScreenEnd, bytes.last == 0x3b else { throw RecordingError.gifEncoding }
        let trailer = bytes.count - 1
        if first {
            // The encoder may label a single image GIF87a even with a loop extension.
            try file.write(contentsOf: Data("GIF89a".utf8))
            try file.write(contentsOf: bytes[6..<trailer])
            return
        }

        let globalPalette = bytes[packedFields]
        let hasGlobalPalette = globalPalette & 0x80 != 0
        let paletteBytes = hasGlobalPalette ? 3 * (2 << Int(globalPalette & 0x07)) : 0
        let extensionsStart = logicalScreenEnd + paletteBytes
        var imageStart = extensionsStart
        // Walk extension sub-blocks to the image separator. Preserve Image I/O's
        // graphic control extension, including the frame delay and disposal method.
        while imageStart + 2 < trailer, bytes[imageStart] == 0x21 {
            imageStart += 2
            while imageStart < trailer {
                let length = Int(bytes[imageStart])
                imageStart += length + 1
                if length == 0 { break }
            }
        }
        let descriptorEnd = imageStart + 10
        guard descriptorEnd < trailer, bytes[imageStart] == 0x2c else { throw RecordingError.gifEncoding }
        try file.write(contentsOf: bytes[extensionsStart..<imageStart])
        if bytes[descriptorEnd - 1] & 0x80 != 0 {
            try file.write(contentsOf: bytes[imageStart..<trailer])
        } else {
            guard hasGlobalPalette else { throw RecordingError.gifEncoding }
            // A later frame may have a different palette. Move its global table
            // into its image block as a local table.
            try file.write(contentsOf: bytes[imageStart..<(descriptorEnd - 1)])
            try file.write(contentsOf: Data([bytes[descriptorEnd - 1] | 0x80 | (globalPalette & 0x07)]))
            try file.write(contentsOf: bytes[logicalScreenEnd..<extensionsStart])
            try file.write(contentsOf: bytes[descriptorEnd..<trailer])
        }
    }
}
