import AppKit
import CoreGraphics
import Foundation
import CoreText
import Testing
@testable import zento

struct ScreenshotScrollStitcherTests {
    private func page(width w: Int = 320, height h: Int = 1600) throws -> CGImage {
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

    @Test func wideFramesAlignVerticallyAndRejectHorizontalMovement() async throws {
        let page = try page(width: 2487, height: 1500)
        func crop(x: Int = 0, y: Int) throws -> CGImage {
            try #require(page.cropping(to: CGRect(x: x, y: y, width: 2483, height: 1171)))
        }
        let stitcher = ScreenshotScrollStitcher()
        _ = try await stitcher.append(crop(y: 0))
        let update = try #require(await stitcher.append(crop(y: 120)))
        #expect(update.height == 1291)
        await #expect(throws: ScreenshotScrollStitcher.Failure.self) {
            _ = try await stitcher.append(crop(x: 4, y: 240))
        }
        _ = try await stitcher.append(crop(y: 240))
        let expected = try #require(page.cropping(to: CGRect(x: 0, y: 0, width: 2483, height: 1411)))
        #expect(try await pixels(stitcher.finish()) == pixels(expected))
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

    @Test(arguments: [false, true]) func fractionalDownwardFramesKeepCumulativeHeight(text: Bool) async throws {
        let page = try text ? textPage(width: 320) : page(), stitcher = ScreenshotScrollStitcher()
        let source = [UInt8](try pixels(page))
        func fractionalFrame(_ y: Int) throws -> CGImage {
            var bytes = [UInt8](repeating: 255, count: 320 * 600 * 4)
            for row in 0..<600 {
                for x in 0..<(320 * 4) {
                    let a = Int(source[(y + row) * 320 * 4 + x])
                    let b = Int(source[(y + row + 1) * 320 * 4 + x])
                    bytes[row * 320 * 4 + x] = UInt8((a + b) / 2)
                }
            }
            let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
            return try #require(CGImage(width: 320, height: 600, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: 1280, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        }
        _ = try await stitcher.append(frame(page, 0))
        for y in [120, 240, 360] {
            let update = try #require(await stitcher.append(fractionalFrame(y)))
            #expect(abs(update.height - (600 + y + 1)) <= 1)
            #expect(try await stitcher.append(fractionalFrame(y)) == nil)
        }
    }

    @Test func transientFailureRecoversButPersistentFailurePauses() async throws {
        let page = try page(), stitcher = ScreenshotScrollStitcher()
        let start = ContinuousClock.now
        _ = try await stitcher.append(frame(page, 0), capturedAt: start)
        #expect(try await stitcher.append(frame(page, 950), capturedAt: start.advanced(by: .milliseconds(100))) == nil)
        let recovered = try #require(await stitcher.append(frame(page, 120), capturedAt: start.advanced(by: .milliseconds(200))))
        #expect(recovered.height == 720)
        #expect(try await stitcher.append(frame(page, 950), capturedAt: start.advanced(by: .milliseconds(300))) == nil)
        await #expect(throws: ScreenshotScrollStitcher.Failure.self) {
            _ = try await stitcher.append(frame(page, 950), capturedAt: start.advanced(by: .milliseconds(800)))
        }
        #expect(try await stitcher.finish().height == 720)
    }

    @MainActor @Test func completedSelectionDoesNotContaminateScrollingFrames() async throws {
        let width = 2959, height = 1193, pageHeight = 1800
        func context(height: Int) throws -> CGContext {
            try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        }
        let pageContext = try context(height: pageHeight)
        pageContext.setFillColor(CGColor(gray: 0.12, alpha: 1))
        pageContext.fill(CGRect(x: 0, y: 0, width: width, height: pageHeight))
        for row in 0..<42 {
            let text = NSAttributedString(string: "Row \(row): scrolling content \(row * 7919)", attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 16, nil),
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.65, alpha: 1)
            ])
            pageContext.textPosition = CGPoint(x: 48, y: 10 + row * 42)
            CTLineDraw(CTLineCreateWithAttributedString(text), pageContext)
        }
        let page = try #require(pageContext.makeImage())
        let view = ScreenshotSelectionView(frame: CGRect(x: 0, y: 0, width: 1800, height: 1100))
        view.mode = .scrolling
        view.selected = { _, _ in }
        func event(_ type: NSEvent.EventType, at point: CGPoint) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 0))
        }
        view.mouseDown(with: try event(.leftMouseDown, at: CGPoint(x: 100, y: 100)))
        view.mouseDragged(with: try event(.leftMouseDragged,
            at: CGPoint(x: 100 + Double(width) / 2, y: 100 + Double(height) / 2)))
        // Match the production transition after the area has been chosen.
        view.finishChoosing()
        func capturedFrame(y: Int) throws -> CGImage {
            let canvas = try context(height: height)
            let crop = try #require(page.cropping(to: CGRect(x: 0, y: y, width: width, height: height)))
            canvas.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))
            canvas.scaleBy(x: 2, y: 2)
            canvas.translateBy(x: -100, y: -100)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: canvas, flipped: false)
            view.draw(view.bounds)
            NSGraphicsContext.restoreGraphicsState()
            let rendered = try #require(canvas.makeImage())
            #expect(try pixels(rendered) == pixels(crop))
            return rendered
        }
        let stitcher = ScreenshotScrollStitcher()
        _ = try await stitcher.append(capturedFrame(y: 0))
        for y in [44, 208, 342, 350] {
            let update = try #require(await stitcher.append(capturedFrame(y: y)))
            #expect(update.height == height + y)
        }
        let expected = try #require(page.cropping(to: CGRect(x: 0, y: 0, width: width, height: height + 350)))
        #expect(try await pixels(stitcher.finish()) == pixels(expected))
    }

    @Test func largeDownwardMovementWithOverlap() async throws {
        let page = try page(), stitcher = ScreenshotScrollStitcher()
        _ = try await stitcher.append(frame(page, 0))
        let update = try #require(await stitcher.append(frame(page, 480)))
        #expect(update.height == 1080)
        #expect(try await stitcher.append(frame(page, 480)) == nil)
        _ = try await stitcher.append(frame(page, 560))
        let expected = try #require(page.cropping(to: CGRect(x: 0, y: 0, width: 320, height: 1160)))
        #expect(try await pixels(stitcher.finish()) == pixels(expected))
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
    private func textPage(width: Int = 800) throws -> CGImage {
        let context = try #require(CGContext(data: nil, width: width, height: 1800, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: 1800))
        for row in 0..<60 {
            let text = NSAttributedString(string: "Row \(row): scrolling screenshot content \(row * 7919)", attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 14, nil),
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)
            ])
            context.textPosition = CGPoint(x: 24, y: 10 + row * 30)
            CTLineDraw(CTLineCreateWithAttributedString(text), context)
        }
        return try #require(context.makeImage())
    }

    @Test func sparseTextAndFixedHeaderDoNotSilentlyProduceBadSeams() async throws {
        let page = try textPage(), stitcher = ScreenshotScrollStitcher()
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
