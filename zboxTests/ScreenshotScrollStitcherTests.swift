import CoreGraphics
import Foundation
import CoreText
import Testing
@testable import zbox

struct ScreenshotScrollStitcherTests {
    private func page() throws -> CGImage {
        let w = 320, h = 1600
        var bytes = [UInt8](repeating: 255, count: w * h * 4)
        var seed: UInt64 = 42
        for y in 0..<h {
            for x in 0..<w {
                seed = seed &* 6364136223846793005 &+ 1
                let value = UInt8(truncatingIfNeeded: seed >> 32)
                let i = (y * w + x) * 4
                bytes[i] = value; bytes[i + 1] = value; bytes[i + 2] = value
            }
        }
        let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
        return try #require(CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }
    private func frame(_ page: CGImage, _ y: Int) throws -> CGImage {
        try #require(page.cropping(to: CGRect(x: 0, y: y, width: page.width, height: 600)))
    }
    private func pixels(_ image: CGImage) throws -> Data {
        let c = try #require(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        c.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Data(bytes: try #require(c.data), count: image.width * image.height * 4)
    }

    @Test func stitchesNativePixelsWithoutDuplicatingStationaryFrames() async throws {
        let page = try page(), stitcher = ScreenshotScrollStitcher()
        let first = try frame(page, 0)
        _ = try await stitcher.append(first)
        #expect(try await stitcher.append(first) == nil)
        for y in [90, 210, 370] {
            let update = try #require(await stitcher.append(frame(page, y)))
            #expect(update.height == 600 + y)
            #expect(update.preview.width <= 240 && update.preview.height <= 720)
        }
        let result = try await stitcher.finish()
        let expected = try #require(page.cropping(to: CGRect(x: 0, y: 0, width: 320, height: 970)))
        #expect(try pixels(result) == pixels(expected))
    }

    @Test func failedAndReverseFramesPreserveLastReliableReference() async throws {
        let page = try page(), stitcher = ScreenshotScrollStitcher()
        _ = try await stitcher.append(frame(page, 0))
        _ = try await stitcher.append(frame(page, 150))
        await #expect(throws: ScreenshotScrollStitcher.Failure.self) { _ = try await stitcher.append(frame(page, 30)) }
        await #expect(throws: ScreenshotScrollStitcher.Failure.self) { _ = try await stitcher.append(frame(page, 950)) }
        let update = try #require(await stitcher.append(frame(page, 250)))
        #expect(update.height == 850)
        let result = try await stitcher.finish()
        let expected = try #require(page.cropping(to: CGRect(x: 0, y: 0, width: 320, height: 850)))
        #expect(try pixels(result) == pixels(expected))
    }

    @Test func limitRejectsNewStripWithoutLosingCapturedContent() async throws {
        let page = try page(), stitcher = ScreenshotScrollStitcher(maximumPixels: 320 * 700)
        _ = try await stitcher.append(frame(page, 0))
        _ = try await stitcher.append(frame(page, 100))
        await #expect(throws: ScreenshotScrollStitcher.Failure.self) { _ = try await stitcher.append(frame(page, 150)) }
        #expect(try await stitcher.finish().height == 700)
    }

    @Test func cancellationDoesNotAppendAFrame() async throws {
        let page = try page(), stitcher = ScreenshotScrollStitcher()
        _ = try await stitcher.append(frame(page, 0))
        let next = try frame(page, 120)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await stitcher.append(next)
        }
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        #expect(try await stitcher.finish().height == 600)
    }
    @Test func sparseTextAndFixedHeaderDoNotSilentlyProduceBadSeams() async throws {
        let context = try #require(CGContext(data: nil, width: 800, height: 1800, bitsPerComponent: 8,
            bytesPerRow: 3200, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 800, height: 1800))
        for row in 0..<60 {
            let text = NSAttributedString(string: "Row \(row): scrolling screenshot content \(row * 7919)", attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 14, nil),
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)
            ])
            context.textPosition = CGPoint(x: 24, y: 10 + row * 30)
            CTLineDraw(CTLineCreateWithAttributedString(text), context)
        }
        let page = try #require(context.makeImage()), stitcher = ScreenshotScrollStitcher()
        _ = try await stitcher.append(frame(page, 0))
        let update = try #require(await stitcher.append(frame(page, 143)))
        #expect(update.height == 743)
        let moved = try frame(page, 280)
        let header = try #require(CGContext(data: nil, width: 800, height: 600, bitsPerComponent: 8,
            bytesPerRow: 3200, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        header.draw(moved, in: CGRect(x: 0, y: 0, width: 800, height: 600))
        header.setFillColor(CGColor(gray: 0.3, alpha: 1))
        header.fill(CGRect(x: 0, y: 520, width: 800, height: 80))
        let changed = try #require(header.makeImage())
        await #expect(throws: ScreenshotScrollStitcher.Failure.self) { _ = try await stitcher.append(changed) }
        #expect(try await stitcher.finish().height == 743)
    }

    @Test func similarNeighboringRowsDoNotShiftTheSeam() async throws {
        let w = 320, h = 1200
        var bytes = [UInt8](repeating: 255, count: w * h * 4)
        var seed: UInt64 = 123
        let anchors = (0..<(w * (h / 32 + 2))).map { _ -> Int in
            seed = seed &* 6364136223846793005 &+ 1
            return Int((seed >> 32) & 255)
        }
        for y in 0..<h {
            for x in 0..<w {
                // Unique horizontal texture with smoothly interpolated vertical rows.
                let a = anchors[(y / 32) * w + x], b = anchors[(y / 32 + 1) * w + x]
                let value = UInt8((a * (32 - y % 32) + b * (y % 32)) / 32)
                let i = (y * w + x) * 4
                bytes[i] = value; bytes[i + 1] = value; bytes[i + 2] = value
            }
        }
        let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
        let page = try #require(CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let stitcher = ScreenshotScrollStitcher()
        _ = try await stitcher.append(frame(page, 0))
        let update = try #require(await stitcher.append(frame(page, 53)))
        #expect(update.height == 653)
        let expected = try #require(page.cropping(to: CGRect(x: 0, y: 0, width: 320, height: 653)))
        #expect(try await pixels(stitcher.finish()) == pixels(expected))
    }

    private final class CapturePixels {
        let storage: UnsafeMutableRawPointer
        init(count: Int) {
            storage = .allocate(byteCount: count, alignment: 16)
            storage.initializeMemory(as: UInt8.self, repeating: 127, count: count)
        }
        deinit { storage.deallocate() }
    }

    @Test func independentStripsReleaseSourcePixelsAndCancelledWorkerReleasesEngine() async throws {
        var owner: CapturePixels? = CapturePixels(count: 320 * 600 * 4)
        weak var releasedPixels = owner
        var image: CGImage? = try {
            let owner = try #require(owner)
            let source = CGDataProvider(dataInfo: Unmanaged.passRetained(owner).toOpaque(),
                data: owner.storage, size: 320 * 600 * 4, releaseData: { info, _, _ in
                    if let info { Unmanaged<CapturePixels>.fromOpaque(info).release() }
                })
            let provider = try #require(source)
            return try #require(CGImage(width: 320, height: 600, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: 1280, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        }()
        owner = nil
        var stitcher: ScreenshotScrollStitcher? = ScreenshotScrollStitcher()
        weak var releasedEngine = stitcher
        _ = try await stitcher?.append(#require(image))
        image = nil
        #expect(releasedPixels == nil)
        let next = try frame(page(), 0)
        let worker = Task { [engine = try #require(stitcher)] in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await engine.append(next)
        }
        await #expect(throws: CancellationError.self) { _ = try await worker.value }
        stitcher = nil
        #expect(releasedEngine == nil)
    }

}
