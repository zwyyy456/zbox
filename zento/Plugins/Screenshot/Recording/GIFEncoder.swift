import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Owned by the capture output's synchronized state. Retains the latest capture and
// one pending visual frame so identical samples can share a delay. Image I/O only
// receives one cropped image at a time.
nonisolated final class GIFEncoder {
    private let file: FileHandle
    private let frameRate: Int
    private let size: CGSize
    private var sourceFrame: PixelFrame?
    private var pendingFrame: PixelFrame?
    private var pendingRect = CGRect.zero
    private var pendingDelay = 0
    private var hasWrittenFrame = false
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
        if isCancelled() { throw CancellationError() }
        sourceFrame = try PixelFrame(image)
    }

    func finish(at seconds: Double, isCancelled: () -> Bool) throws {
        guard !isClosed else { return }
        guard sourceFrame != nil else { throw RecordingError.emptyVideo }
        // GIF delays are centiseconds. Round boundaries, not each delay, so 15 fps stays accurate.
        let end = max(2, Int((min(seconds, Double(RecordingOptions.gifLimit)) * 100).rounded(.down)))
        try writeCompletedFrames(until: Double(end) / 100, isCancelled: isCancelled)
        let start = boundary(nextFrame)
        let remaining = end - start
        if remaining >= 2, let sourceFrame {
            try appendSample(sourceFrame, delay: remaining, isCancelled: isCancelled)
            nextFrame += 1
        }
        try flushPending(isCancelled: isCancelled)
        if isCancelled() { throw CancellationError() }
        try file.write(contentsOf: Data([0x3b]))
        try file.close()
        sourceFrame = nil
        pendingFrame = nil
        isClosed = true
    }

    private func boundary(_ index: Int) -> Int {
        (index * 100 + frameRate / 2) / frameRate
    }

    private func writeCompletedFrames(until seconds: Double, isCancelled: () -> Bool) throws {
        guard let sourceFrame else { return }
        let end = Int((seconds * 100).rounded(.down))
        let start = boundary(nextFrame)
        while boundary(nextFrame + 1) <= end {
            if isCancelled() { throw CancellationError() }
            nextFrame += 1
        }
        let delay = boundary(nextFrame) - start
        if delay > 0 {
            try appendSample(sourceFrame, delay: delay, isCancelled: isCancelled)
        }
    }

    private func appendSample(_ frame: PixelFrame, delay: Int, isCancelled: () -> Bool) throws {
        if isCancelled() { throw CancellationError() }
        let rect: CGRect
        if let pendingFrame {
            guard let changed = try frame.changedRect(from: pendingFrame, isCancelled: isCancelled) else {
                pendingDelay += delay
                return
            }
            rect = changed
            try flushPending(isCancelled: isCancelled)
        } else {
            rect = CGRect(origin: .zero, size: size)
        }
        pendingFrame = frame
        pendingRect = rect
        pendingDelay = delay
    }

    private func flushPending(isCancelled: () -> Bool) throws {
        guard let pendingFrame else { return }
        if isCancelled() { throw CancellationError() }
        try autoreleasepool {
            let image = try pendingFrame.image(in: pendingRect)
            try Self.writeFrame(image, rect: pendingRect, delay: Double(pendingDelay) / 100,
                                first: !hasWrittenFrame, to: file)
        }
        hasWrittenFrame = true
    }

    private static func writeFrame(_ image: CGImage, rect: CGRect, delay: Double, first: Bool, to file: FileHandle) throws {
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

        var bytes = buffer as Data
        let logicalScreenEnd = 13
        let packedFields = 10
        guard bytes.count > logicalScreenEnd, bytes.last == 0x3b else { throw RecordingError.gifEncoding }
        let trailer = bytes.count - 1

        let globalPalette = bytes[packedFields]
        let hasGlobalPalette = globalPalette & 0x80 != 0
        let paletteBytes = hasGlobalPalette ? 3 * (2 << Int(globalPalette & 0x07)) : 0
        let extensionsStart = logicalScreenEnd + paletteBytes
        var imageStart = extensionsStart
        // Keep the canvas between patches. Opaque patches also erase pixels where
        // a cursor or window used to be, instead of leaving transparent trails.
        while imageStart + 2 < trailer, bytes[imageStart] == 0x21 {
            if bytes[imageStart + 1] == 0xf9 {
                guard imageStart + 8 <= trailer, bytes[imageStart + 2] == 4 else {
                    throw RecordingError.gifEncoding
                }
                bytes[imageStart + 3] = 0x04 // Disposal 1, no transparency or user input.
            }
            imageStart += 2
            while imageStart < trailer {
                let length = Int(bytes[imageStart])
                imageStart += length + 1
                if length == 0 { break }
            }
        }
        let descriptorEnd = imageStart + 10
        guard descriptorEnd < trailer, bytes[imageStart] == 0x2c else { throw RecordingError.gifEncoding }
        guard let left = UInt16(exactly: Int(rect.minX)), let top = UInt16(exactly: Int(rect.minY)) else {
            throw RecordingError.gifEncoding
        }
        bytes[imageStart + 1] = UInt8(truncatingIfNeeded: left)
        bytes[imageStart + 2] = UInt8(truncatingIfNeeded: left >> 8)
        bytes[imageStart + 3] = UInt8(truncatingIfNeeded: top)
        bytes[imageStart + 4] = UInt8(truncatingIfNeeded: top >> 8)
        if first {
            // The first full frame establishes and resets the canvas on every loop.
            try file.write(contentsOf: Data("GIF89a".utf8))
            try file.write(contentsOf: bytes[6..<trailer])
            return
        }
        try file.write(contentsOf: bytes[extensionsStart..<imageStart])
        if bytes[descriptorEnd - 1] & 0x80 != 0 {
            try file.write(contentsOf: bytes[imageStart..<trailer])
        } else {
            guard hasGlobalPalette else { throw RecordingError.gifEncoding }
            // A later frame may have a different palette. Move its global table
            // into its image block as a local table.
            try file.write(contentsOf: bytes[imageStart..<(descriptorEnd - 1)])
            try file.write(contentsOf: Data([(bytes[descriptorEnd - 1] & 0x78) | 0x80 | (globalPalette & 0x07)]))
            try file.write(contentsOf: bytes[logicalScreenEnd..<extensionsStart])
            try file.write(contentsOf: bytes[descriptorEnd..<trailer])
        }
    }

    private struct PixelFrame {
        private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let width: Int
        let height: Int
        let pixels: Data
        private var rowBytes: Int { width * 4 }
        private static var bitmapInfo: UInt32 {
            CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        }

        init(_ image: CGImage) throws {
            width = image.width
            height = image.height
            var pixels = Data(count: width * height * 4)
            try pixels.withUnsafeMutableBytes { storage in
                guard let context = CGContext(data: storage.baseAddress, width: image.width, height: image.height,
                                              bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                              space: Self.colorSpace, bitmapInfo: Self.bitmapInfo) else {
                    throw RecordingError.gifEncoding
                }
                let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
                // A GIF recording has an opaque canvas. Flatten captured transparency
                // against black so a later transparent pixel can erase an earlier one.
                context.setFillColor(CGColor(gray: 0, alpha: 1))
                context.fill(bounds)
                context.draw(image, in: bounds)
            }
            self.pixels = pixels
        }

        func changedRect(from previous: PixelFrame, isCancelled: () -> Bool) throws -> CGRect? {
            try pixels.withUnsafeBytes { current in
                try previous.pixels.withUnsafeBytes { old in
                    var left = width, top = height, right = -1, bottom = -1
                    for row in 0..<height {
                        if isCancelled() { throw CancellationError() }
                        let offset = row * rowBytes
                        if memcmp(current.baseAddress! + offset, old.baseAddress! + offset, rowBytes) == 0 { continue }
                        var first = 0
                        while current.loadUnaligned(fromByteOffset: offset + first * 4, as: UInt32.self)
                            == old.loadUnaligned(fromByteOffset: offset + first * 4, as: UInt32.self) {
                            first += 1
                        }
                        var last = width - 1
                        while last > first,
                              current.loadUnaligned(fromByteOffset: offset + last * 4, as: UInt32.self)
                                == old.loadUnaligned(fromByteOffset: offset + last * 4, as: UInt32.self) {
                            last -= 1
                        }
                        left = min(left, first)
                        right = max(right, last)
                        top = min(top, row)
                        bottom = row
                    }
                    guard right >= left else { return nil }
                    return CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)
                }
            }
        }

        func image(in rect: CGRect) throws -> CGImage {
            guard let provider = CGDataProvider(data: pixels as CFData),
                  let full = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                     bytesPerRow: rowBytes, space: Self.colorSpace,
                                     bitmapInfo: CGBitmapInfo(rawValue: Self.bitmapInfo), provider: provider,
                                     decode: nil, shouldInterpolate: false, intent: .defaultIntent),
                  let cropped = full.cropping(to: rect) else {
                throw RecordingError.gifEncoding
            }
            return cropped
        }
    }

}
