import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Owned by the capture output's synchronized state. Keeps only one pending frame;
// each completed frame is encoded and written immediately, never accumulated in Image I/O.
nonisolated final class GIFEncoder {
    private let file: FileHandle
    private let frameRate: Int
    private let size: CGSize
    private var image: CGImage?
    private var nextFrame = 0
    private var isClosed = false

    init(url: URL, size: CGSize, frameRate: Int) throws {
        self.size = size
        self.frameRate = frameRate
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw RecordingError.gifEncoding
        }
        file = try FileHandle(forWritingTo: url)
    }

    deinit { try? file.close() }

    func append(_ image: CGImage, at seconds: Double, isCancelled: () -> Bool) throws {
        guard !isClosed else { return }
        guard image.width == Int(size.width), image.height == Int(size.height) else {
            throw RecordingError.unexpectedSize
        }
        try writeCompletedFrames(until: min(seconds, Double(RecordingOptions.gifLimit)), isCancelled: isCancelled)
        self.image = image
    }

    func finish(at seconds: Double, isCancelled: () -> Bool) throws {
        guard !isClosed else { return }
        guard image != nil else { throw RecordingError.emptyVideo }
        // GIF delays are centiseconds. Round boundaries, not each delay, so 15 fps stays accurate.
        let end = max(2, Int((min(seconds, Double(RecordingOptions.gifLimit)) * 100).rounded(.down)))
        try writeCompletedFrames(until: Double(end) / 100, isCancelled: isCancelled)
        let start = boundary(nextFrame)
        let remaining = end - start
        if remaining >= 2, let image {
            if isCancelled() { throw CancellationError() }
            try Self.writeFrame(image, delay: Double(remaining) / 100, first: nextFrame == 0, to: file)
            nextFrame += 1
        }
        if isCancelled() { throw CancellationError() }
        try file.write(contentsOf: Data([0x3b]))
        try file.close()
        image = nil
        isClosed = true
    }

    private func boundary(_ index: Int) -> Int {
        (index * 100 + frameRate / 2) / frameRate
    }

    private func writeCompletedFrames(until seconds: Double, isCancelled: () -> Bool) throws {
        guard let image else { return }
        let end = Int((seconds * 100).rounded(.down))
        while boundary(nextFrame + 1) <= end {
            if isCancelled() { throw CancellationError() }
            let delay = Double(boundary(nextFrame + 1) - boundary(nextFrame)) / 100
            try autoreleasepool {
                try Self.writeFrame(image, delay: delay, first: nextFrame == 0, to: file)
            }
            nextFrame += 1
        }
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
