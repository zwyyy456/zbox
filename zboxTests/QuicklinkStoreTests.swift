import Foundation
import Testing
@testable import zbox

@MainActor struct QuicklinkStoreTests {
    @Test func preservesSavedDataAndRejectsFailedWrites() throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "quicklinks.json")
        let store = QuicklinkStore(fileURL: url)
        var item = Quicklink(name: "Example", target: "https://example.com")
        try store.save(item)
        item.name = "Renamed"
        try store.save(item)
        #expect(QuicklinkStore(fileURL: url).items == [item])
        let corrupt = Data("invalid json".utf8)
        try corrupt.write(to: url)
        let damaged = QuicklinkStore(fileURL: url)
        #expect(throws: (any Error).self) { try damaged.save(item) }
        #expect(try Data(contentsOf: url) == corrupt)
        let blocked = QuicklinkStore(fileURL: url.appending(path: "child.json"))
        #expect(throws: (any Error).self) { try blocked.save(item) }
        #expect(blocked.items.isEmpty)
    }
}
