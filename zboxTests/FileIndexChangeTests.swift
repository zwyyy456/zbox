import Foundation
import Testing
@testable import zbox

struct FileIndexChangeTests {
    @Test func coalescesSubtreesWithoutConfusingPathPrefixes() {
        var change = FileIndexChange(directories: ["docs", "docs/sub", "docs-other"], eventID: 10)
        change.merge(FileIndexChange(directories: ["code"], eventID: 8))
        #expect(change.minimalDirectories == ["code", "docs", "docs-other"])
        #expect(change.eventID == 10)
        change.merge(FileIndexChange(directories: [""], eventID: 12))
        #expect(change.minimalDirectories == [""])
        #expect(change.eventID == 12)
    }

    @Test func advancesEventCursorOnlyAfterSuccessfulReconciliation() async throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let rootURL = folder.appending(path: "root")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try Data().write(to: rootURL.appending(path: "file.txt"))
        let root = try FileSearchRoot.selected(rootURL)
        let store = FileIndexStore(url: folder.appending(path: "index.sqlite"))
        let scanner = FileIndexScanner()
        try await scanner.reconcile(root, change: FileIndexChange(directories: [""], eventID: 10), store: store)
        #expect(try await store.cursor(root: root.id) == 10)
        try FileManager.default.removeItem(at: rootURL)
        await #expect(throws: (any Error).self) {
            try await scanner.reconcile(root, change: FileIndexChange(directories: [""], eventID: 20), store: store)
        }
        #expect(try await store.cursor(root: root.id) == 10)
        #expect(try await store.files(root: root.id).count == 1)
        try await store.clear()
        #expect(try await store.cursor(root: root.id) == nil)
        #expect(try await store.files(root: root.id).isEmpty)
    }
}
