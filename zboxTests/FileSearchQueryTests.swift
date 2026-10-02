import Foundation
import Testing
@testable import zbox

struct FileSearchQueryTests {
    private let root = FileSearchRoot(url: URL(fileURLWithPath: "/Projects/zbox"), volumeID: "test", fileID: 1)

    @Test func combinesLiteralTermsAndFilters() throws {
        let file = IndexedFile(rootID: root.id, path: "docs/年度 报告.PDF", name: "年度 报告.PDF", isDirectory: false, size: 0, modified: .distantPast)
        #expect(try FileSearchQuery("\"年度 报告\" ext:pdf path:zbox type:file").score(file, root: root) != nil)
        #expect(try FileSearchQuery("年度 ext:txt").score(file, root: root) == nil)
        #expect(try FileSearchQuery("报告 type:folder").score(file, root: root) == nil)
        let unicode = IndexedFile(rootID: root.id, path: "cafe\u{301}.txt", name: "cafe\u{301}.txt", isDirectory: false, size: 0, modified: .distantPast)
        #expect(try FileSearchQuery("CAFÉ").score(unicode, root: root) == 2)
        for input in ["\"unfinished", "ext:", "type:unknown", "path:"] {
            #expect(throws: (any Error).self) { try FileSearchQuery(input) }
        }
    }

    @Test func limitsOnlyAfterRankingAllMatches() async throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = FileIndexStore(url: folder.appending(path: "index.sqlite"))
        let names = ["zzz-report", "report-final", "report"]
        try await store.upsert(names.map { IndexedFile(rootID: root.id, path: $0, name: $0, isDirectory: false, size: 0, modified: .distantPast) }, generation: UUID())
        let page = try await store.search(FileSearchQuery("report"), roots: [root], sort: .relevance, limit: 2)
        #expect(page.files.map(\.name) == ["report", "report-final"])
        #expect(page.hasMore)
        let task = Task { try Task.checkCancellation(); return try await store.search(FileSearchQuery("report"), roots: [root], sort: .name) }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
