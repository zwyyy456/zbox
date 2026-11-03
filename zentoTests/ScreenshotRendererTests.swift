import CoreGraphics
import ImageIO
import Testing
@testable import zento

@MainActor
struct ScreenshotRendererTests {
    @Test func mosaicChangesOnlySelectedPixelsAndPreservesSolidCovers() async throws {
        let context = try #require(CGContext(data: nil, width: 48, height: 24, bitsPerComponent: 8, bytesPerRow: 192,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 48, height: 24))
        for x in 0..<24 {
            context.setFillColor(CGColor(gray: x.isMultiple(of: 2) ? 0 : 1, alpha: 1))
            context.fill(CGRect(x: x, y: 0, width: 1, height: 24))
        }
        let image = try #require(context.makeImage())
        let edit = ScreenshotEdit(crop: CGRect(x: 0, y: 0, width: 48, height: 24), marks: [
            ScreenshotMark(tool: .redact, start: CGPoint(x: 6, y: 6), end: CGPoint(x: 12, y: 12), text: ""),
            ScreenshotMark(tool: .mosaic, start: .zero, end: CGPoint(x: 24, y: 24), text: "")
        ])
        let baseline = try await ScreenshotRenderer.flattened(image: image, edit: ScreenshotEdit(crop: edit.crop))
        context.draw(baseline, in: edit.crop)
        let outside = (3 * 48 + 36) * 4
        let baselineBytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        let originalOutside = Array(UnsafeBufferPointer(start: baselineBytes + outside, count: 4))
        let result = try await ScreenshotRenderer.flattened(image: image, edit: edit)
        context.draw(result, in: CGRect(x: 0, y: 0, width: 48, height: 24))
        let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        let left = (3 * 48 + 1) * 4
        let neighbor = (3 * 48 + 22) * 4
        #expect(bytes[left] > 0 && bytes[left] < 255)
        #expect(bytes[left] == bytes[neighbor])
        // CGContext storage rows are top-down relative to the image drawing coordinates.
        let covered = ((24 - 1 - 8) * 48 + 8) * 4
        #expect(bytes[covered] == 0 && bytes[covered + 1] == 0 && bytes[covered + 2] == 0)
        #expect(Array(UnsafeBufferPointer(start: bytes + outside, count: 4)) == originalOutside)
    }

    @Test func editingTextReplacesOneAnnotationAndCanBeUndone() throws {
        let context = try #require(CGContext(data: nil, width: 100, height: 80, bitsPerComponent: 8, bytesPerRow: 400,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let document = ScreenshotDocument(image: try #require(context.makeImage()))
        let point = CGPoint(x: 10, y: 20)
        document.commit(ScreenshotMark(tool: .text, start: point, end: point, text: "First", textSize: 36))
        document.replaceText(at: 0, with: ScreenshotMark(tool: .text, start: point, end: point, text: "Edited", textSize: 36))
        #expect(document.edit.marks.count == 1)
        #expect(document.edit.marks[0].text == "Edited")
        #expect(document.edit.marks[0].textSize == 36)
        document.undo()
        #expect(document.edit.marks[0].text == "First")
        document.redo()
        #expect(document.edit.marks[0].text == "Edited")
    }

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
