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
}
