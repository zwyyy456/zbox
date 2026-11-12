import CGIF
import CoreGraphics
import Foundation

// Owned by the capture output's synchronized state. Retains the latest capture and
// one pending visual frame so identical samples can share a delay. CGIF copies
// each submitted frame and keeps a bounded queue for delta encoding.
nonisolated final class GIFEncoder {
    private let url: URL
    private var encoder: OpaquePointer?
    private let frameRate: Int
    private let size: CGSize
    private var sourceFrame: PixelFrame?
    private var pendingFrame: PixelFrame?
    private var pendingDelay = 0
    private var nextFrame = 0
    private var isClosed = false

    init(url: URL, size: CGSize, frameRate: Int) throws {
        guard UInt16(exactly: size.width) != nil, UInt16(exactly: size.height) != nil,
              size.width > 0, size.height > 0 else { throw RecordingError.unexpectedSize }
        self.url = url
        self.size = size
        self.frameRate = frameRate
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw RecordingError.gifEncoding
        }
    }

    deinit {
        if let encoder { cgif_rgb_close(encoder) }
    }

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
        let end = max(2, Int((min(seconds, Double(RecordingOptions.gifLimit)) * 100).nextUp.rounded(.down)))
        try writeCompletedFrames(until: Double(end) / 100, isCancelled: isCancelled)
        let start = boundary(nextFrame)
        let remaining = end - start
        if remaining >= 2, let sourceFrame {
            try appendSample(sourceFrame, delay: remaining, isCancelled: isCancelled)
            nextFrame += 1
        }
        try flushPending(isCancelled: isCancelled)
        if isCancelled() { throw CancellationError() }
        guard let encoder else { throw RecordingError.emptyVideo }
        self.encoder = nil // close consumes the C instance, including on failure.
        guard cgif_rgb_close(encoder) == CGIF_OK else { throw RecordingError.gifEncoding }
        if isCancelled() { throw CancellationError() }
        sourceFrame = nil
        pendingFrame = nil
        isClosed = true
    }

    private func boundary(_ index: Int) -> Int {
        (index * 100 + frameRate / 2) / frameRate
    }

    private func writeCompletedFrames(until seconds: Double, isCancelled: () -> Bool) throws {
        guard let sourceFrame else { return }
        // Preserve exact centisecond boundaries such as 2.3 s when binary
        // floating-point multiplication falls one representable value below them.
        let end = Int((seconds * 100).nextUp.rounded(.down))
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
        if let pendingFrame {
            if frame.pixels == pendingFrame.pixels {
                pendingDelay += delay
                return
            }
            try flushPending(isCancelled: isCancelled)
        }
        pendingFrame = frame
        pendingDelay = delay
    }

    private func flushPending(isCancelled: () -> Bool) throws {
        guard let pendingFrame else { return }
        if isCancelled() { throw CancellationError() }
        if encoder == nil {
            var config = CGIFrgb_Config()
            config.width = UInt16(size.width)
            config.height = UInt16(size.height)
            config.numLoops = 0
            encoder = url.withUnsafeFileSystemRepresentation { path in
                config.path = path
                return cgif_rgb_newgif(&config)
            }
        }
        guard let encoder else { throw RecordingError.gifEncoding }
        let result = pendingFrame.pixels.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            var config = CGIFrgb_FrameConfig()
            // The upstream API copies the bytes synchronously and does not mutate them.
            config.pImageData = UnsafeMutablePointer(mutating: bytes.bindMemory(to: UInt8.self).baseAddress!)
            config.fmtChan = CGIF_CHAN_FMT_RGBA
            config.attrFlags = UInt32(CGIF_RGB_FRAME_ATTR_NO_DITHERING)
            config.genFlags = UInt32(CGIF_FRAME_GEN_USE_DIFF_WINDOW)
            config.delay = UInt16(pendingDelay) // At most the 30-second recording limit.
            return cgif_rgb_addframe(encoder, &config)
        }
        guard result == CGIF_OK else { throw RecordingError.gifEncoding }
        if isCancelled() { throw CancellationError() }
    }

    private struct PixelFrame {
        private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let pixels: Data
        private static var bitmapInfo: UInt32 {
            CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        }

        init(_ image: CGImage) throws {
            let width = image.width
            let height = image.height
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
    }
}
