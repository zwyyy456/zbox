import Accelerate
import CoreGraphics
import Foundation
import OSLog

/// ScreenCaptureKit frames stay at native resolution. Only independently copied new strips
/// survive ingestion; cropping alone can retain the entire source frame's backing storage.
actor ScreenshotScrollStitcher {
    private static let logger = Logger(subsystem: "tech.hyperseek.zento", category: "ScreenshotScroll")
    private var frameNumber = 0
    private var unmatchedSince: ContinuousClock.Instant?

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
    private var roundingRemainder = 0.0

    init(maximumPixels: Int = 32_000_000) { self.maximumPixels = maximumPixels }

    func append(_ image: CGImage) throws -> Update? {
        // CoreGraphics temporaries must drain per frame, not at the end of a
        // potentially minutes-long capture task.
        try autoreleasepool { try appendFrame(image) }
    }

    func append(_ image: CGImage, capturedAt: ContinuousClock.Instant) throws -> Update? {
        do {
            let update = try append(image)
            unmatchedSince = nil
            return update
        } catch Failure.alignment {
            if let unmatchedSince, unmatchedSince.duration(to: capturedAt) >= .milliseconds(500) {
                self.unmatchedSince = nil
                throw Failure.alignment
            }
            if unmatchedSince == nil { unmatchedSince = capturedAt }
            Self.logger.info("Waiting for reliable overlap; reference unchanged")
            return nil
        }
    }

    private func appendFrame(_ image: CGImage) throws -> Update? {
        try Task.checkCancellation()
        frameNumber += 1
        Self.logger.info("Frame \(self.frameNumber): size=\(image.width)x\(image.height), acceptedHeight=\(self.height)")
        guard image.width >= 64, image.height >= 64,
              image.width * image.height <= 16_000_000 else { throw Failure.dimensions }
        if reference != nil, image.width != width || image.height != reference?.height { throw Failure.dimensions }
        let gray = try GrayFrame(image)
        let addition: Int
        var remainder = roundingRemainder
        if let reference {
            let movement = try Self.displacement(previous: reference, current: gray)
            if movement == 0 { return nil }
            let accumulated = movement + remainder
            addition = Int(accumulated.rounded())
            remainder = accumulated - Double(addition)
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
        roundingRemainder = remainder
        width = image.width
        height = nextHeight
        Self.logger.info("Accepted: addedRows=\(addition), totalRows=\(self.height), strips=\(self.strips.count)")
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
        let samples: [Float]
        let sampleWidth: Int
        let width: Int
        let height: Int
        init(_ source: CGImage) throws {
            width = source.width; height = source.height
            guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue),
                  let data = context.data else { throw ScreenshotError.captureFailed }
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
            pixels = Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: width * height))
            let columns = Array(stride(from: 0, to: width, by: max(1, width / 96)))
            sampleWidth = columns.count
            var samples = [Float]()
            samples.reserveCapacity(sampleWidth * height)
            for y in 0..<height {
                for x in columns { samples.append(Float(pixels[y * width + x])) }
            }
            self.samples = samples

        }
    }

    private static func displacement(previous: GrayFrame, current: GrayFrame) throws -> Double {
        if previous.pixels == current.pixels { return 0 }
        let maximum = current.height - max(32, current.height * 15 / 100)
        var scores = [Double](repeating: -1, count: maximum + 1)
        var best = 0
        for offset in 0...maximum {
            try Task.checkCancellation()
            scores[offset] = correlation(previous, current, offset: Double(offset))
            if scores[offset] > scores[best] { best = offset }
        }
        // Neighboring rows belong to one peak. Compare independent peaks instead.
        let competitor = scores.indices.filter { abs($0 - best) > 3 }.map { scores[$0] }.max() ?? -1
        let quality = scores[best]
        logger.info("Vertical candidate: offset=\(best), correlation=\(quality), otherPeak=\(competitor), overlap=\(current.height - best)")
        var movement = Double(best)
        // Refine on the original pixels, including fractional scroll positions.
        for step in -3...3 {
            let candidate = Double(best) + Double(step) / 4
            guard candidate >= 0, candidate <= Double(maximum) else { continue }
            if correlation(previous, current, offset: candidate) > correlation(previous, current, offset: movement) {
                movement = candidate
            }
        }
        let refinedQuality = correlation(previous, current, offset: movement)
        guard refinedQuality >= 0.85, refinedQuality - competitor >= 0.015 else {
            logger.info("Rejected candidate: offset=\(movement), refinedCorrelation=\(refinedQuality), peakGap=\(refinedQuality - competitor)")
            _ = correlation(previous, current, offset: movement, logBands: true)
            throw Failure.alignment
        }
        logger.info("Confirmed vertical movement=\(movement)")
        return movement
    }

    private static func correlation(_ a: GrayFrame, _ b: GrayFrame, offset: Double, logBands: Bool = false) -> Double {
        let row = Int(offset), fraction = offset - Double(row)
        let overlap = a.height - row - (fraction > 0 ? 1 : 0)
        var worst = 1.0
        var informativeBands = 0
        for band in 0..<3 {
            let start = band * overlap / 3, end = (band + 1) * overlap / 3
            let count = Double((end - start) * a.sampleWidth)
            var sumA: Float = 0, sumB: Float = 0, squareA: Float = 0, squareB: Float = 0, product: Float = 0
            a.samples.withUnsafeBufferPointer { ap in
                b.samples.withUnsafeBufferPointer { bp in
                    let left = ap.baseAddress! + (start + row) * a.sampleWidth
                    let right = bp.baseAddress! + start * b.sampleWidth
                    let length = vDSP_Length(Int(count))
                    func measure(_ values: UnsafePointer<Float>) {
                        vDSP_sve(values, 1, &sumA, length)
                        vDSP_sve(right, 1, &sumB, length)
                        vDSP_svesq(values, 1, &squareA, length)
                        vDSP_svesq(right, 1, &squareB, length)
                        vDSP_dotpr(values, 1, right, 1, &product, length)
                    }
                    if fraction == 0 { measure(left) }
                    else {
                        var interpolated = [Float](repeating: 0, count: Int(count))
                        var weight = Float(fraction)
                        vDSP_vintb(left, 1, left + a.sampleWidth, 1, &weight, &interpolated, 1, length)
                        interpolated.withUnsafeBufferPointer { measure($0.baseAddress!) }
                    }
                }
            }
            let varianceA = Double(squareA) - Double(sumA) * Double(sumA) / count
            let varianceB = Double(squareB) - Double(sumB) * Double(sumB) / count
            if varianceA / count < 4 && varianceB / count < 4 { continue }
            guard varianceA > 0, varianceB > 0 else { return -1 }
            informativeBands += 1
            let score = (Double(product) - Double(sumA) * Double(sumB) / count) / sqrt(varianceA * varianceB)
            if logBands {
                logger.info("Overlap band=\(band), correlation=\(score), varianceA=\(varianceA / count), varianceB=\(varianceB / count)")
            }
            worst = min(worst, score)
        }
        return informativeBands >= 2 ? worst : -1
    }
}
