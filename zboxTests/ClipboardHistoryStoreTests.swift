import Foundation
import Testing
@testable import zbox

@MainActor
struct ClipboardHistoryStoreTests {
    @Test
    func persistsExactTextDeduplicatesAndDeletes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("test.store")
        let payload = ClipboardPayload(kind: "text", text: " sample\n", data: Data(" sample\n".utf8), sourceBundleID: "test.app")
        var store: ClipboardHistoryStore? = try ClipboardHistoryStore(url: url)
        try store?.add(payload, at: Date(timeIntervalSince1970: 1))
        try store?.add(payload, at: Date(timeIntervalSince1970: 2))
        let entries = try #require(try store?.entries())
        #expect(entries.count == 1)
        #expect(entries.first?.copiedAt == Date(timeIntervalSince1970: 2))
        store = nil
        let reopened = try ClipboardHistoryStore(url: url)
        let id = try #require(entries.first?.id)
        #expect(try reopened.payload(for: id)?.text == payload.text)
        try reopened.delete(id)
        #expect(try reopened.entries().isEmpty)
        try reopened.add(payload)
        try reopened.clear()
        #expect(try reopened.entries().isEmpty)
    }

    @Test
    func evictsUnpinnedItemsAndPrunesWithoutRemovingPins() throws {
        let store = try ClipboardHistoryStore(inMemory: true)
        let start = Date(timeIntervalSince1970: 1_000_000)
        for index in 0..<500 {
            let text = "fixture-\(index)"
            try store.add(ClipboardPayload(kind: "text", text: text, data: Data(text.utf8), sourceBundleID: nil),
                          at: start.addingTimeInterval(Double(index)))
        }
        let original = try store.entries()
        let oldest = try #require(original.last)
        try store.setPinned(true, for: oldest.id)
        let next = ClipboardPayload(kind: "text", text: "next", data: Data("next".utf8), sourceBundleID: nil)
        try store.add(next, at: start.addingTimeInterval(501))
        let after = try store.entries()
        #expect(after.count == 500)
        #expect(after.contains { $0.id == oldest.id })
        #expect(!after.contains { $0.text == "fixture-1" })
        for entry in after { try store.setPinned(true, for: entry.id) }
        #expect(throws: ClipboardHistoryError.storageFull) {
            try store.add(ClipboardPayload(kind: "text", text: "rejected", data: Data("rejected".utf8), sourceBundleID: nil))
        }
        #expect(try store.entries().count == 500)
        for entry in after where entry.id != oldest.id { try store.setPinned(false, for: entry.id) }
        try store.prune(days: 7, now: start.addingTimeInterval(9 * 86_400))
        #expect(try store.entries().map(\.id) == [oldest.id])
        try store.clear()
        #expect(try store.entries().isEmpty)
    }

}
