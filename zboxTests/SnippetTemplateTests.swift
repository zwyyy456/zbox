import AppKit
import Testing
@testable import zbox

struct SnippetTemplateTests {
    @Test func rendersOneSnapshotWithoutRecursiveExpansion() throws {
        var reads = 0
        let template = SnippetTemplate("{{date}} {{time}} {{clipboard}} / {{clipboard}} / \\{{date}} / {{unknown}}")
        let output = try template.render(at: Date(timeIntervalSince1970: 0), timeZone: try #require(TimeZone(secondsFromGMT: 0))) {
            reads += 1
            return "{{date}}"
        }
        #expect(output == "1970-01-01 00:00 {{date}} / {{date}} / {{date}} / {{unknown}}")
        #expect(reads == 1)
        #expect(try SnippetTemplate("plain text").render { throw SnippetClipboardError.noText } == "plain text")
        #expect(throws: (any Error).self) {
            try SnippetTemplate("prefix {{clipboard}} suffix").render { throw SnippetClipboardError.noText }
        }
    }

    @MainActor @Test func rejectsPrivateClipboardAndDoesNotWritePartialResults() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("fixture", forType: .string)
        #expect(try SnippetClipboard.read(from: board) == "fixture")
        for marker in ClipboardContentPolicy.ignoredTypes {
            board.clearContents()
            board.setString("private fixture", forType: .string)
            board.setData(Data(), forType: .init(marker))
            let before = board.changeCount
            #expect(throws: (any Error).self) {
                try SnippetTemplate("{{clipboard}}").render { try SnippetClipboard.read(from: board) }
            }
            #expect(board.changeCount == before)
        }
        board.clearContents()
        #expect(throws: (any Error).self) { try SnippetClipboard.read(from: board) }
    }
}
