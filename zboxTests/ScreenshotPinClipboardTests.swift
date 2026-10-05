import AppKit
import Testing
@testable import zbox

@MainActor
struct ScreenshotPinClipboardTests {
    @Test func acceptsAnImageAndRejectsPrivateOrFileContents() async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let context = try #require(CGContext(data: nil, width: 20, height: 12, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let data = try await ScreenshotRenderer.encode(try #require(context.makeImage()), format: .png)
        board.setData(data, forType: .png)
        let image = try await ScreenshotPinClipboard.decode(ScreenshotPinClipboard.read(from: board))
        #expect(image.width == 20 && image.height == 12)
        board.setString("private", forType: .init("org.nspasteboard.ConcealedType"))
        #expect(throws: ScreenshotError.self) { try ScreenshotPinClipboard.read(from: board) }
        board.clearContents()
        board.setData(data, forType: .png)
        board.setString("file:///tmp/example.png", forType: .fileURL)
        #expect(throws: ScreenshotError.self) { try ScreenshotPinClipboard.read(from: board) }
        await #expect(throws: ScreenshotError.self) { try await ScreenshotPinClipboard.decode(Data([0, 1, 2])) }
    }
}
