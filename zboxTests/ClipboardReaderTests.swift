import AppKit
import Testing
@testable import zbox

@MainActor
struct ClipboardReaderTests {
    @Test
    func readsIsolatedTextAndRejectsPrivateOrExcludedContent() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("sample\ntext", forType: .string)
        let entry = try #require(try ClipboardReader.read(from: board, excluding: [], sourceBundleID: "test.app"))
        #expect(entry.text == "sample\ntext")
        #expect(entry.sourceBundleID == "test.app")
        #expect(try ClipboardReader.read(from: board, excluding: ["test.app"], sourceBundleID: "test.app") == nil)
        board.clearContents()
        board.setString(String(repeating: "x", count: ClipboardReader.textLimit + 1), forType: .string)
        #expect(throws: ClipboardHistoryError.tooLarge) {
            _ = try ClipboardReader.read(from: board, excluding: [], sourceBundleID: nil)
        }
        for marker in ClipboardReader.ignoredTypes {
            board.clearContents()
            board.setString("private fixture", forType: .string)
            board.setData(Data(), forType: .init(marker))
            #expect(try ClipboardReader.read(from: board, excluding: [], sourceBundleID: nil) == nil)
        }
    }

    @Test
    func temporaryAccessChangesRevisionButOwnWritesOnlyMarkTheirChangeCount() {
        let access = ClipboardAccessCoordinator()
        let initialRevision = access.revision
        access.beginTemporaryAccess()
        #expect(access.temporaryAccessCount == 1)
        #expect(access.revision != initialRevision)
        access.endTemporaryAccess()
        #expect(access.temporaryAccessCount == 0)
        let completedRevision = access.revision
        access.didWrite(changeCount: 42)
        #expect(access.revision == completedRevision)
        #expect(access.ignoredChangeCount == 42)
    }

    @Test
    func acceptsPNGAndRejectsInvalidOrOversizedImages() throws {
        let representation = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 8, bitsPerPixel: 32))
        let data = try #require(representation.representation(using: .png, properties: [:]))
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setData(data, forType: .png)
        let payload = try #require(try ClipboardReader.read(from: board, excluding: [], sourceBundleID: nil))
        #expect(payload.kind == "png")
        #expect(payload.data == data)
        #expect(throws: ClipboardHistoryError.unsupported) {
            _ = try ClipboardImage.dimensions(of: Data("not an image".utf8))
        }
        #expect(throws: ClipboardHistoryError.tooLarge) {
            _ = try ClipboardImage.dimensions(of: Data(count: ClipboardImage.byteLimit + 1))
        }
    }

}
