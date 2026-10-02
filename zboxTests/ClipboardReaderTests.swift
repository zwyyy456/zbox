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
        for marker in ClipboardReader.ignoredTypes {
            board.clearContents()
            board.setString("private fixture", forType: .string)
            board.setData(Data(), forType: .init(marker))
            #expect(try ClipboardReader.read(from: board, excluding: [], sourceBundleID: nil) == nil)
        }
    }

    @Test
    func temporaryAccessAndOwnWritesInvalidatePendingCapture() {
        let access = ClipboardAccessCoordinator()
        let initialRevision = access.revision
        access.beginTemporaryAccess()
        #expect(access.temporaryAccessCount == 1)
        #expect(access.revision != initialRevision)
        access.endTemporaryAccess()
        #expect(access.temporaryAccessCount == 0)
        access.didWrite(changeCount: 42)
        #expect(access.ignoredChangeCount == 42)
    }
}
