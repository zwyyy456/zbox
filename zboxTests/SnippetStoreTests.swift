import Foundation
import Testing
@testable import zbox

@MainActor struct SnippetStoreTests {
    @Test func preservesTextAndExistingDataOnStorageFailure() throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "snippets.json")
        let store = SnippetStore(fileURL: url)
        let item = Snippet(name: "Template", body: "  中文\n{{date}}\n")
        try store.save(item)
        #expect(SnippetStore(fileURL: url).items == [item])
        let corrupt = Data("invalid json".utf8)
        try corrupt.write(to: url)
        let damaged = SnippetStore(fileURL: url)
        #expect(throws: (any Error).self) { try damaged.save(item) }
        #expect(try Data(contentsOf: url) == corrupt)
        let blocked = SnippetStore(fileURL: url.appending(path: "child.json"))
        #expect(throws: (any Error).self) { try blocked.save(item) }
        #expect(blocked.items.isEmpty)
    }
}
