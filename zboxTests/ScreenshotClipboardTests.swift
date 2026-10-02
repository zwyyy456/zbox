import AppKit
import Testing
@testable import zbox

@MainActor
struct ScreenshotClipboardTests {
    @Test func uploadCompletionPreservesInterveningCopyAndMarksOwnWrites() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let coordinator = ClipboardAccessCoordinator()
        let url = try #require(URL(string: "https://images.example.com/folder/test%20image.png"))
        board.setString("before upload", forType: .string)
        let startedAt = board.changeCount
        board.clearContents()
        board.setString("new user copy", forType: .string)
        #expect(!ScreenshotClipboard.copyLink(url, format: .markdown, to: board, coordinator: coordinator, ifUnchangedSince: startedAt))
        #expect(board.string(forType: .string) == "new user copy")
        #expect(ScreenshotClipboard.copyLink(url, format: .markdown, to: board, coordinator: coordinator, ifUnchangedSince: board.changeCount))
        #expect(board.string(forType: .string) == "![Screenshot](<https://images.example.com/folder/test%20image.png>)")
        #expect(coordinator.ignoredChangeCount == board.changeCount)
    }
}
