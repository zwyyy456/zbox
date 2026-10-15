import Foundation
import Testing
@testable import zbox

struct FileMappedIndexTests {
    private func file(_ root: UUID, _ path: String, size: Int64 = 1) -> IndexedFile {
        IndexedFile(rootID: root, path: path, name: (path as NSString).lastPathComponent,
                    isDirectory: false, size: size, modified: Date(timeIntervalSince1970: Double(size)))
    }

    @Test func snapshotAndOverlayPreserveRankingUnicodeAndFilters() async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var root = FileSearchRoot(url: URL(fileURLWithPath: "/Projects"), volumeID: "test", fileID: 1)
        root.exclusions = ["excluded"]
        let store = FileIndexStore(url: directory)
        var files = (0..<450).map { file(root.id, "folder\($0)/report.txt", size: Int64($0)) }
        files += (0..<400).map { file(root.id, "prefix/report-\($0).txt", size: Int64($0)) }
        files += (0..<400).map { file(root.id, "suffix/\($0)-report.txt", size: Int64($0)) }
        files += [file(root.id, "REPORT"), file(root.id, "年度 报告.pdf"), file(root.id, "cafe\u{301}.txt"),
                  file(root.id, ".hidden/report.txt"), file(root.id, "excluded/report.txt"), file(root.id, "report"),
                  file(root.id, "unicode/é.txt"), file(root.id, "unicode/e\u{301}.txt-copy"),
                  file(root.id, "unicode/Å.txt"), file(root.id, "unicode/A\u{30a}.txt-copy"),
                  file(root.id, "unicode/\u{e000}.txt"), file(root.id, "unicode/\u{10000}.txt")]
        try await store.upsert(files, generation: UUID())
        try await store.setCursor(10, root: root.id, persist: true)
        let reopened = FileIndexStore(url: directory)
        #expect(try await reopened.cursor(root: root.id) == 10)
        #expect(try await reopened.files(root: root.id).count == files.count)
        for input in ["report", "CAFÉ", "年度 ext:pdf", "ext:txt path:folder2", "type:file", "不存在", "r", "é", "å", "path:unicode"] {
            let query = try FileSearchQuery(input)
            for sort in FileSearchSort.allCases {
                let expected = files.compactMap { item -> (IndexedFile, Int)? in
                    query.score(item, root: root).map { (item, $0) }
                }.sorted { a, b in
                    if sort == .relevance, a.1 != b.1 { return a.1 > b.1 }
                    if sort == .modified, a.0.modified != b.0.modified { return a.0.modified > b.0.modified }
                    let first = IndexedFile.normalized(a.0.name), second = IndexedFile.normalized(b.0.name)
                    return first == second ? a.0.path < b.0.path : first < second
                }
                let page = try await reopened.search(query, roots: [root], sort: sort)
                #expect(page.files == Array(expected.prefix(200).map(\.0)))
                #expect(page.hasMore == (expected.count > 200))
            }
        }
        let generation = UUID()
        let changed = file(root.id, "folder0/renamed.txt", size: 99)
        try await reopened.upsert([changed], generation: generation)
        try await reopened.finishScan(root: root.id, directory: "folder0", generation: generation)
        let live = try await reopened.files(root: root.id)
        #expect(live.contains(changed))
        #expect(!live.contains { $0.path == "folder0/report.txt" })
        try await reopened.setCursor(20, root: root.id, persist: true)
        let third = FileIndexStore(url: directory)
        #expect(try await third.files(root: root.id) == live)
        #expect(try await third.cursor(root: root.id) == 20)
    }

    @Test func canonicalBuildOrderingAndASCIIQueryPrefilterMatchSwift() async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = FileSearchRoot(url: URL(fileURLWithPath: "/Unicode"), volumeID: "test", fileID: 1)
        let names = ["年度项目报告-9876", "Project项目-9876-Report报告", "café-42", "cafe\u{301}-42",
                     "Å-42", "A\u{30a}-42", "a\u{315}\u{300}-42", "à\u{315}-42", "İ-42", "i\u{307}-42",
                     "가-42", "\u{1100}\u{1161}-42", "👩🏽‍💻-42", "\u{e000}-42", "\u{10000}-42", "K-42", "K-42"]
        let files = names.enumerated().map { file(root.id, "dir\($0.offset)/\($0.element)") }
        let store = FileIndexStore(url: directory)
        try await store.upsert(files, generation: UUID())
        try await store.setCursor(1, root: root.id, persist: true)
        let mapped = try FileMappedIndex(url: directory.appending(path: root.id.uuidString + ".index"))
        let actualNames = try (0..<mapped.nameCount).map { try mapped.name($0) }
        let expectedNames = names.sorted {
            let a = IndexedFile.normalized($0), b = IndexedFile.normalized($1)
            return a == b ? $0 < $1 : a < b
        }
        #expect(actualNames == expectedNames)
        for input in ["-42", "café-42", "cafe\u{301}-42", "年度项目报告-9876", "project项目-9876",
                      "i", "i\u{307}", "à", "가-42", "👩🏽‍💻-42", "k-42", "42 不存在"] {
            let query = try FileSearchQuery(input)
            let actual = try await store.search(query, roots: [root], sort: .name)
            let expected = Set(files.filter { query.score($0, root: root) != nil }.map(\.path))
            #expect(Set(actual.files.map(\.path)) == expected, "query: \(input)")
        }
    }

    @Test func compactPathsPreserveOriginalUTF8AndFractionalDates() async throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let root = UUID()
        let paths = ["a/café.txt", "b/cafe\u{301}.txt", "café/one.txt", "cafe\u{301}/two.txt", "top.txt"]
        let files = paths.map { path in
            IndexedFile(rootID: root, path: path, name: (path as NSString).lastPathComponent,
                isDirectory: false, size: 1, modified: Date(timeIntervalSinceReferenceDate: 813456789.1234567))
        }
        let store = FileIndexStore(url: folder)
        try await store.upsert(files, generation: UUID())
        #expect(try await store.files(root: root).allSatisfy { $0.modified == files[0].modified })
        try await store.setCursor(1, root: root, persist: true)
        let reopened = FileIndexStore(url: folder)
        let restored = try await reopened.files(root: root)
        #expect(Set(restored.map { Data($0.path.utf8) }) == Set(paths.map { Data($0.utf8) }))
        #expect(restored.allSatisfy { $0.modified == files[0].modified })
    }

    @Test func searchSnapshotsSurviveConcurrentRootRemovalAndCancellation() async throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let root = FileSearchRoot(url: URL(fileURLWithPath: "/Selected"), volumeID: "test", fileID: 1)
        let store = FileIndexStore(url: folder)
        let files = (0..<4200).map { file(root.id, "folder/报告-\($0).txt") }
        try await store.upsert(files, generation: UUID())
        try await store.setCursor(1, root: root.id, persist: true)
        let query = try FileSearchQuery("type:file")
        try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<8 {
                group.addTask { try await store.search(query, roots: [root], sort: .name, limit: 5000).files.count }
            }
            group.addTask { try await store.remove(root: root.id); return 0 }
            for try await count in group { #expect(count == 0 || count == files.count) }
        }
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await store.search(query, roots: [root], sort: .name)
        }
        await #expect(throws: CancellationError.self) { try await cancelled.value }
    }

    @Test func emptySnapshotAndBuildCountBoundary() throws {
        let url = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try FileMappedIndex.write(count: 0, fileAt: { _ in
            Issue.record("An empty build must not request a record")
            return file(UUID(), "unexpected")
        }, cursor: 7, to: url)
        let empty = try FileMappedIndex(url: url)
        #expect(empty.count == 0)
        #expect(empty.cursor == 7)
        #expect(throws: FileMappedIndex.FormatError.self) {
            try FileMappedIndex.write(count: Int(UInt32.max) + 1, fileAt: { _ in
                Issue.record("An unrepresentable count must fail before reading records")
                return file(UUID(), "unexpected")
            }, cursor: 8, to: url)
        }
        #expect(try FileMappedIndex(url: url).cursor == 7)
    }

    @Test func malformedSnapshotsRebuildWithoutAFalseCursor() async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let root = UUID(), entry = file(UUID(), "file")
        let snapshot = directory.appending(path: root.uuidString + ".index")
        try FileMappedIndex.write(count: 1, fileAt: { _ in entry }, cursor: 42, to: snapshot)
        let good = try Data(contentsOf: snapshot)
        var badOffset = good
        badOffset.replaceSubrange(64..<72, with: repeatElement(UInt8(255), count: 8))
        var badCount = good
        badCount.replaceSubrange(24..<32, with: repeatElement(UInt8(255), count: 8))
        var badVersion = good
        badVersion[8] = 99
        for data in [Data(good.prefix(20)), badOffset, badCount, badVersion] {
            try data.write(to: snapshot, options: .atomic)
            let store = FileIndexStore(url: directory)
            #expect(try await store.cursor(root: root) == nil)
            #expect(try await store.files(root: root).isEmpty)
            try await store.upsert([file(root, "rebuilt")], generation: UUID())
            try await store.setCursor(50, root: root, persist: true)
            #expect(try FileMappedIndex(url: snapshot).cursor == 50)
        }
    }

    @Test func concurrentCompactionPreservesNewChangesAndRootRemoval() async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = UUID(), other = UUID()
        let store = FileIndexStore(url: directory)
        let initial = (0..<4_200).map { file(root, "initial/\($0).txt") }
        try await store.upsert(initial, generation: UUID())
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await store.setCursor(1, root: root, persist: true) }
            for i in 0..<100 {
                let entry = file(root, "new/\(i).txt")
                group.addTask { try await store.upsert([entry], generation: UUID()) }
            }
            try await group.waitForAll()
        }
        #expect(try await store.files(root: root).count == 4_300)
        try await store.setCursor(2, root: root, persist: true)
        try await store.upsert([file(other, "other")], generation: UUID())
        try await store.setCursor(3, root: other, persist: true)
        try await store.remove(root: root)
        let reopened = FileIndexStore(url: directory)
        #expect(try await reopened.cursor(root: root) == nil)
        #expect(try await reopened.files(root: other).count == 1)
        try await reopened.clear()
        let cleared = FileIndexStore(url: directory)
        #expect(try await cleared.cursor(root: other) == nil)
    }
    @Test func unsavedChangesReplayFromDurableCursorAndSubtreePruningIsExact() async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = UUID()
        let store = FileIndexStore(url: directory)
        let initial = ["docs", "docs/old", "docs-other/keep", "docs2/keep"].map { file(root, $0) }
        try await store.upsert(initial, generation: UUID())
        try await store.setCursor(10, root: root, persist: true)
        let generation = UUID()
        try await store.upsert([file(root, "docs/new")], generation: generation)
        try await store.finishScan(root: root, directory: "docs", generation: generation)
        try await store.setCursor(20, root: root)
        #expect(Set(try await store.files(root: root).map(\.path)) == ["docs/new", "docs-other/keep", "docs2/keep"])
        #expect(try await store.cursor(root: root) == 20)
        let reopened = FileIndexStore(url: directory)
        #expect(try await reopened.cursor(root: root) == 10)
        #expect(Set(try await reopened.files(root: root).map(\.path)) == Set(initial.map(\.path)))
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await store.setCursor(30, root: root, persist: true)
        }
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        #expect(try await reopened.cursor(root: root) == 10)
        try await store.setCursor(20, root: root, persist: true)
        await store.releaseMemory()
        #expect(try await store.cursor(root: root) == 20)
        #expect(Set(try await store.files(root: root).map(\.path)) == ["docs/new", "docs-other/keep", "docs2/keep"])
    }

    @Test func directoryCandidatesMatchFullPathSemanticsAcrossBoundaries() async throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        var root = FileSearchRoot(url: URL(fileURLWithPath: "/Root/项目"), volumeID: "test", fileID: 1)
        root.exclusions = ["excluded"]
        let paths = ["docs/report.txt", "docs2/other.txt", "else/docs.txt", "docs/sub/report.pdf",
                     "else/项目-report.txt", "cafe\u{301}/CAFÉ.txt", "excluded/report.txt", ".hidden/report.txt"]
        let files = paths.map { file(root.id, $0) }
        let store = FileIndexStore(url: folder)
        try await store.upsert(files, generation: UUID())
        try await store.setCursor(1, root: root.id, persist: true)
        for input in ["ext:txt path:docs", "path:docs/rep", "path:项目/docs", "path:docs/", "path:/Root/项目",
                      "path:项目 path:report", "path:else path:docs", "path:café/caf", "path:missing/name", "path:/", "path:docs path:pdf"] {
            let query = try FileSearchQuery(input)
            let actual = try await store.search(query, roots: [root], sort: .name)
            let expected = Set(files.filter { query.score($0, root: root) != nil }.map(\.path))
            #expect(Set(actual.files.map(\.path)) == expected, "query: \(input)")
        }
    }

    @Test func lowercaseNormalizationCannotCauseBytePrefilterFalseNegatives() async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = FileSearchRoot(url: URL(fileURLWithPath: "/Unicode"), volumeID: "test", fileID: 1)
        let files = [file(root.id, "a/Ϊ́-42.txt"), file(root.id, "b/ΐ-42.txt")]
        let store = FileIndexStore(url: directory)
        try await store.upsert(files, generation: UUID())
        for input in ["ΐ", "Ϊ́", "path:ΐ", "path:Ϊ́"] {
            let query = try FileSearchQuery(input)
            #expect(try await store.search(query, roots: [root], sort: .name).files.count == 2)
        }
        try await store.setCursor(1, root: root.id, persist: true)
        for input in ["ΐ", "Ϊ́", "path:ΐ", "path:Ϊ́"] {
            let query = try FileSearchQuery(input)
            #expect(try await store.search(query, roots: [root], sort: .name).files.count == 2)
        }
    }

}
