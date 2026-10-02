import CoreGraphics
import ImageIO
import Testing
@testable import zbox

@MainActor
struct ScreenshotRendererTests {
    @Test func exportsOnlyCroppedFlattenedPixelsAndSupportsUndo() async throws {
        let context = try #require(CGContext(data: nil, width: 20, height: 12, bitsPerComponent: 8, bytesPerRow: 80,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 20, height: 12))
        let document = ScreenshotDocument(image: try #require(context.makeImage()))
        document.commit(ScreenshotMark(tool: .redact, start: CGPoint(x: 3, y: 2), end: CGPoint(x: 13, y: 10), text: ""))
        document.commit(ScreenshotMark(tool: .crop, start: CGPoint(x: 3, y: 2), end: CGPoint(x: 13, y: 10), text: ""))
        document.undo()
        #expect(document.edit.crop.size == CGSize(width: 20, height: 12))
        document.redo()
        let data = try await ScreenshotRenderer.export(image: document.image, edit: document.edit, format: .png)
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        #expect(CGImageSourceGetCount(source) == 1)
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 10)
        #expect(image.height == 8)
        let pixels = try #require(CGContext(data: nil, width: 10, height: 8, bitsPerComponent: 8, bytesPerRow: 40,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        pixels.draw(image, in: CGRect(x: 0, y: 0, width: 10, height: 8))
        let bytes = try #require(pixels.data).assumingMemoryBound(to: UInt8.self)
        for offset in stride(from: 0, to: 320, by: 4) {
            #expect(bytes[offset] == 0 && bytes[offset + 1] == 0 && bytes[offset + 2] == 0 && bytes[offset + 3] == 255)
        }
    }
}
