import CoreGraphics
import Foundation
import Vision

/// ScreenCaptureKit frames stay at native resolution. Only independently copied new strips
/// survive ingestion; cropping alone can retain the entire source frame's backing storage.
actor ScreenshotScrollStitcher {
    enum Failure: Error { case alignment, limit, dimensions }
    struct Update: Sendable {
        let preview: CGImage
        let height: Int
    }
    private let maximumPixels: Int
    private var strips: [CGImage] = []
    private var reference: GrayFrame?
    private var width = 0
    private var height = 0

    init(maximumPixels: Int = 32_000_000) { self.maximumPixels = maximumPixels }

    func append(_ image: CGImage) throws -> Update? {
        // Vision/CoreGraphics temporaries must drain per frame, not at the end of a
        // potentially minutes-long capture task.
        try autoreleasepool { try appendFrame(image) }
    }

    private func appendFrame(_ image: CGImage) throws -> Update? {
        try Task.checkCancellation()
        guard image.width >= 64, image.height >= 64,
              image.width * image.height <= 16_000_000 else { throw Failure.dimensions }
        if reference != nil, image.width != width || image.height != reference?.height { throw Failure.dimensions }
        let gray = try GrayFrame(image)
        let addition: Int
        if let reference {
            addition = try Self.displacement(previous: reference, current: gray)
            if addition == 0 { return nil }
        } else { addition = image.height }
        guard image.width * (height + addition) <= maximumPixels,
              height + addition <= 60_000, strips.count < 512 else { throw Failure.limit }
        guard let crop = image.cropping(to: CGRect(x: 0, y: image.height - addition, width: image.width, height: addition)),
              let context = Self.context(width: image.width, height: addition) else { throw ScreenshotError.captureFailed }
        context.draw(crop, in: CGRect(x: 0, y: 0, width: image.width, height: addition))
        guard let strip = context.makeImage() else { throw ScreenshotError.captureFailed }
        let nextStrips = strips + [strip]
        let nextHeight = height + addition
        let preview = try Self.render(strips: nextStrips, width: image.width, height: nextHeight, preview: true)
        try Task.checkCancellation()
        // Commit pixels and their preview together. Cancellation or a preview failure
        // must leave the last user-visible result and reference unchanged.
        strips = nextStrips
        reference = gray
        width = image.width
        height = nextHeight
        return Update(preview: preview, height: height)
    }

    func finish() throws -> CGImage {
        try Task.checkCancellation()
        let image = try autoreleasepool { try Self.render(strips: strips, width: width, height: height, preview: false) }
        try Task.checkCancellation()
        strips.removeAll()
        reference = nil
        return image
    }

    private static func render(strips: [CGImage], width: Int, height: Int, preview: Bool) throws -> CGImage {
        guard height > 0 else { throw ScreenshotError.captureFailed }
        let scale = preview ? min(1, min(240 / Double(width), 720 / Double(height))) : 1
        let w = max(1, Int(Double(width) * scale)), h = max(1, Int(Double(height) * scale))
        guard let context = Self.context(width: w, height: h) else { throw ScreenshotError.exportFailed }
        context.scaleBy(x: CGFloat(w) / CGFloat(width), y: CGFloat(h) / CGFloat(height))
        var top = height
        for strip in strips {
            try Task.checkCancellation()
            top -= strip.height
            context.draw(strip, in: CGRect(x: 0, y: top, width: width, height: strip.height))
        }
        guard let result = context.makeImage() else { throw ScreenshotError.exportFailed }
        return result
    }

    private static func context(width: Int, height: Int) -> CGContext? {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    private struct GrayFrame {
        let pixels: [UInt8]
        let image: CGImage
        let width: Int
        let height: Int
        init(_ source: CGImage) throws {
            width = source.width; height = source.height
            guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue),
                  let data = context.data else { throw ScreenshotError.captureFailed }
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
            pixels = Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: width * height))
            // Vision works on a bounded image, while overlap validation uses native pixels.
            let scale = min(1, 1024 / Double(max(width, height)))
            let w = max(1, Int(Double(width) * scale)), h = max(1, Int(Double(height) * scale))
            guard let small = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
                throw ScreenshotError.captureFailed
            }
            small.draw(source, in: CGRect(x: 0, y: 0, width: w, height: h))
            guard let result = small.makeImage() else { throw ScreenshotError.captureFailed }
            image = result
        }
    }

    private static func displacement(previous: GrayFrame, current: GrayFrame) throws -> Int {
        // Keep the last accepted reference for tiny movements: repeatedly updating it would lose rows.
        if match(previous, current, offset: 0) >= 0.985 { return 0 }
        let request = VNTranslationalImageRegistrationRequest(targetedCGImage: previous.image)
        try VNImageRequestHandler(cgImage: current.image).perform([request])
        try Task.checkCancellation()
        guard let result = request.results?.first, result.confidence >= 0.8,
              abs(result.alignmentTransform.tx) <= 2 else { throw Failure.alignment }
        let scale = Double(current.height) / Double(current.image.height)
        let estimate = Int((abs(result.alignmentTransform.ty) * scale).rounded())
        let radius = max(2, Int(ceil(scale * 2)))
        var best = 0, quality = 0.0
        var ambiguous = false
        // Validate both signs against actual pixels, independent of Vision's coordinate convention.
        for distance in max(1, estimate - radius)...max(1, estimate + radius) {
            try Task.checkCancellation()
            guard distance <= current.height * 3 / 4 else { continue }
            for offset in [distance, -distance] {
                let score = match(previous, current, offset: offset)
                if score > quality {
                    best = offset; quality = score; ambiguous = false
                } else if score == quality { ambiguous = true }
            }
        }
        guard best > 0, quality >= 0.96, !ambiguous else { throw Failure.alignment }
        return best
    }

    private static func match(_ a: GrayFrame, _ b: GrayFrame, offset: Int) -> Double {
        let overlap = a.height - abs(offset)
        guard overlap > 0 else { return 0 }
        var worst = 1.0
        // All three horizontal bands must agree. Fixed headers/footers and changing content
        // must not be mistaken for a valid global translation.
        for band in 0..<3 {
            var matches = 0, count = 0, low = 255, high = 0, difference = 0
            var allMatches = 0, allCount = 0
            let start = band * overlap / 3, end = (band + 1) * overlap / 3
            for y in stride(from: start, to: end, by: max(1, overlap / 192)) {
                for x in stride(from: 0, to: a.width, by: max(1, a.width / 96)) {
                    let p = Int(a.pixels[(y + max(0, offset)) * a.width + x])
                    let q = Int(b.pixels[(y + max(0, -offset)) * b.width + x])
                    allCount += 1
                    if abs(p - q) <= 12 { allMatches += 1 }
                    // Blank margins must not overwhelm a bad match on sparse text,
                    // including the stationary-frame check.
                    let neighbor = min(a.width - 1, x + 3)
                    let ap = Int(a.pixels[(y + max(0, offset)) * a.width + neighbor])
                    let bp = Int(b.pixels[(y + max(0, -offset)) * b.width + neighbor])
                    if abs(p - ap) < 16 && abs(q - bp) < 16 { continue }
                    low = min(low, p); high = max(high, p)
                    if abs(p - q) <= 12 { matches += 1 }
                    count += 1
                    difference += abs(p - q)
                }
            }
            if count == 0 && offset == 0 {
                guard allCount > 0 else { return 0 }
                worst = min(worst, Double(allMatches) / Double(allCount))
            } else {
                guard count >= 32, high - low >= 24 else { return 0 }
                // The threshold alone gives neighboring smooth rows identical scores.
                // Prefer the actual lowest-error alignment instead of the first candidate.
                let score = Double(matches) / Double(count) - Double(difference) / Double(count * 255) * 0.03
                worst = min(worst, score)
            }
        }
        return worst
    }
}
