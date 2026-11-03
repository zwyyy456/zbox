import Foundation
import Testing
@testable import zento

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
    func unlimitedHistorySearchesAndPagesBeyondFiveHundred() throws {
        let store = try ClipboardHistoryStore(inMemory: true)
        let start = Date(timeIntervalSince1970: 1_000_000)
        for index in 0..<501 {
            let text = "fixture-\(index)"
            try store.add(payload(text), at: start.addingTimeInterval(Double(index)))
        }
        #expect(try store.entries(limit: 600).count == 501)
        let first = try store.entries(limit: 100)
        let second = try store.entries(offset: 100, limit: 100)
        #expect(Set(first.map(\.id)).isDisjoint(with: second.map(\.id)))
        #expect(second.first?.text == "fixture-400")
        #expect(try store.entries(query: "FIXTURE-0").map(\.text) == ["fixture-0"])
        try store.prune(days: 0, now: start.addingTimeInterval(365 * 86_400))
        #expect(try store.entries(limit: 600).count == 501)
        #expect(store.totalBytes == (0..<501).reduce(0) { $0 + "fixture-\($1)".utf8.count })
    }

    @Test
    func capacityEvictsOldestUnpinnedAndRejectsWithoutPartialDeletion() throws {
        let store = try ClipboardHistoryStore(inMemory: true)
        let start = Date(timeIntervalSince1970: 1_000_000)
        try store.add(payload("aaa"), at: start)
        let pinned = try #require(try store.entries().first)
        try store.setPinned(true, for: pinned.id)
        try store.add(payload("bbb"), at: start.addingTimeInterval(1))
        try store.add(payload("ccc"), at: start.addingTimeInterval(2), byteLimit: 6)
        #expect(try store.entries().map(\.text) == ["ccc", "aaa"])
        #expect(store.totalBytes == 6)
        #expect(throws: ClipboardHistoryError.storageFull) {
            try store.add(payload("dddd"), byteLimit: 6)
        }
        #expect(try store.entries().map(\.text) == ["ccc", "aaa"])
        #expect(throws: ClipboardHistoryError.storageFull) { try store.applyByteLimit(2) }
        #expect(store.totalBytes == 6)
        try store.applyByteLimit(3)
        #expect(try store.entries().map(\.id) == [pinned.id])
        try store.add(payload("eee"), at: start)
        try store.prune(days: 7, now: start.addingTimeInterval(9 * 86_400))
        #expect(try store.entries().map(\.id) == [pinned.id])
        #expect(store.totalBytes == 3)
        try store.clear()
        #expect(store.totalBytes == 0)
    }

    @Test
    func filtersInDatabaseAndRestoresUsageAfterReopening() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.store")
        var store: ClipboardHistoryStore? = try ClipboardHistoryStore(url: url)
        try store?.add(payload("plain"))
        try store?.add(ClipboardPayload(kind: "link", text: "https://example.com", data: Data("url".utf8), sourceBundleID: nil))
        try store?.add(ClipboardPayload(kind: "png", text: "Picture", data: Data([1, 2]), sourceBundleID: nil))
        #expect(try store?.entries(filter: .text).map(\.text) == ["plain"])
        #expect(try store?.entries(filter: .links).count == 1)
        #expect(try store?.entries(query: "picture", filter: .images).count == 1)
        #expect(try store?.entries(query: "plain", filter: .images).isEmpty == true)
        let id = try #require(try store?.entries(filter: .text).first?.id)
        try store?.setPinned(true, for: id)
        #expect(try store?.entries(filter: .pinned).map(\.id) == [id])
        store = nil
        let reopened = try ClipboardHistoryStore(url: url)
        #expect(reopened.totalBytes == 10)
        try reopened.delete(id)
        #expect(reopened.totalBytes == 5)
    }

    private func payload(_ text: String) -> ClipboardPayload {
        ClipboardPayload(kind: "text", text: text, data: Data(text.utf8), sourceBundleID: nil)
    }
}
