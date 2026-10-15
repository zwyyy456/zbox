import Foundation
import Darwin
import Testing
@testable import zbox

struct FileIndexTests {
    @Test func scansFiltersAndReconcilesDeletedSubtrees() async throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let rootURL = folder.appending(path: "root")
        try FileManager.default.createDirectory(at: rootURL.appending(path: "nested"), withIntermediateDirectories: true)
        try Data().write(to: rootURL.appending(path: "nested/中文.txt"))
        try Data().write(to: rootURL.appending(path: ".hidden"))
        let root = try FileSearchRoot.selected(rootURL)
        let store = FileIndexStore(url: folder.appending(path: "index"))
        let scanner = FileIndexScanner()
        _ = try await scanner.scan(root, store: store)
        #expect(Set(try await store.files(root: root.id).map(\.path)) == ["nested", "nested/中文.txt"])
        try FileManager.default.moveItem(at: rootURL.appending(path: "nested"), to: rootURL.appending(path: "renamed"))
        _ = try await scanner.scan(root, store: store)
        #expect(Set(try await store.files(root: root.id).map(\.path)) == ["renamed", "renamed/中文.txt"])
        try FileManager.default.removeItem(at: rootURL)
        await #expect(throws: (any Error).self) { try await scanner.scan(root, store: store) }
        #expect(try await store.files(root: root.id).count == 2)
    }

    @Test func bulkScanMatchesFoundationMetadataAndHiddenRules() async throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let rootURL = folder.appending(path: "root")
        try FileManager.default.createDirectory(at: rootURL.appending(path: "nested"), withIntermediateDirectories: true)
        for i in 0..<700 {
            try Data(repeating: UInt8(i % 255), count: i % 31).write(to: rootURL.appending(path: "报告-\(i).txt"))
        }
        let hidden = rootURL.appending(path: "flag-hidden.txt")
        try Data([1]).write(to: hidden)
        #expect(chflags(hidden.path, UInt32(UF_HIDDEN)) == 0)
        try Data([1]).write(to: rootURL.appending(path: ".dotfile"))
        try Data([1, 2, 3]).write(to: rootURL.appending(path: "nested/é.txt"))
        var root = try FileSearchRoot.selected(rootURL)
        let scanner = FileIndexScanner()
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        for includesHidden in [false, true] {
            root.includesHidden = includesHidden
            let store = FileIndexStore(url: folder.appending(path: UUID().uuidString))
            _ = try await scanner.scan(root, store: store)
            let actual = try await store.files(root: root.id)
            let enumerator = try #require(FileManager.default.enumerator(at: root.url, includingPropertiesForKeys: Array(keys),
                options: includesHidden ? [] : [.skipsHiddenFiles]))
            let expected: [IndexedFile] = try {
                var expected: [IndexedFile] = []
                for case let url as URL in enumerator {
                    let values = try url.resourceValues(forKeys: keys)
                    let canonical = url.resolvingSymlinksInPath().standardizedFileURL
                    let base = root.url.resolvingSymlinksInPath().standardizedFileURL
                    #expect(FileSearchRoot.contains(canonical, in: base))
                    expected.append(IndexedFile(rootID: root.id, path: String(canonical.path.dropFirst(base.path.count + 1)),
                        name: url.lastPathComponent, isDirectory: values.isDirectory == true,
                        size: Int64(values.fileSize ?? 0), modified: values.contentModificationDate ?? .distantPast))
                }
                return expected
            }()
            let sorted = expected.sorted { $0.path < $1.path }
            #expect(actual.map(\.path) == sorted.map(\.path))
            for (a, b) in zip(actual, sorted).filter({ $0 != $1 }).prefix(3) {
                #expect(a == b)
                #expect(a.size == b.size)
                #expect(a.name == b.name)
                #expect(a.isDirectory == b.isDirectory)
                #expect(a.modified.timeIntervalSinceReferenceDate - b.modified.timeIntervalSinceReferenceDate == 0)
            }
        }
    }

    @Test func unfinishedScanDoesNotPruneSavedRecords() async throws {
        let url = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let root = UUID()
        let store = FileIndexStore(url: url.appending(path: "index"))
        let old = IndexedFile(rootID: root, path: "old", name: "old", isDirectory: false, size: 0, modified: .distantPast)
        try await store.upsert([old], generation: UUID())
        try await store.upsert([], generation: UUID())
        #expect(try await store.files(root: root) == [old])
        try await store.finishScan(root: root, directory: "", generation: UUID())
        #expect(try await store.files(root: root).isEmpty)
    }
    @Test func incrementalScanDoesNotEnterPackagesOrSymbolicLinks() async throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let rootURL = folder.appending(path: "root")
        try FileManager.default.createDirectory(at: rootURL.appending(path: "Example.app/Contents"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folder.appending(path: "outside/nested"), withIntermediateDirectories: true)
        try Data().write(to: rootURL.appending(path: "Example.app/Contents/private.txt"))
        try Data().write(to: folder.appending(path: "outside/nested/private.txt"))
        try FileManager.default.createSymbolicLink(at: rootURL.appending(path: "alias"), withDestinationURL: folder.appending(path: "outside"))
        let root = try FileSearchRoot.selected(rootURL)
        let store = FileIndexStore(url: folder.appending(path: "index"))
        let scanner = FileIndexScanner()
        _ = try await scanner.scan(root, store: store)
        _ = try await scanner.scan(root, directory: "Example.app/Contents", store: store)
        _ = try await scanner.scan(root, directory: "alias/nested", store: store)
        #expect(Set(try await store.files(root: root.id).map(\.path)) == ["Example.app", "alias"])
    }

    @Test func shallowReconciliationPreservesUnvisitedDescendantsAndPrunesVanishedDirectories() async throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let rootURL = folder.appending(path: "root")
        try FileManager.default.createDirectory(at: rootURL.appending(path: "stable"), withIntermediateDirectories: true)
        try Data([1]).write(to: rootURL.appending(path: "stable/deep.txt"))
        try Data([1]).write(to: rootURL.appending(path: "top.txt"))
        let root = try FileSearchRoot.selected(rootURL)
        let store = FileIndexStore(url: folder.appending(path: "index"))
        let scanner = FileIndexScanner()
        _ = try await scanner.scan(root, store: store)
        try await store.setCursor(10, root: root.id, persist: true)
        try Data([1, 2, 3]).write(to: rootURL.appending(path: "stable/deep.txt"))
        try Data([1, 2]).write(to: rootURL.appending(path: "top.txt"))
        try await scanner.reconcile(root, change: FileIndexChange(eventID: 20, shallowDirectories: [""]), store: store)
        let shallow = try await store.files(root: root.id)
        #expect(shallow.first { $0.path == "top.txt" }?.size == 2)
        #expect(shallow.first { $0.path == "stable/deep.txt" }?.size == 1)
        try await scanner.reconcile(root, change: FileIndexChange(directories: ["stable"], eventID: 21), store: store)
        #expect(try await store.files(root: root.id).first { $0.path == "stable/deep.txt" }?.size == 3)
        try FileManager.default.removeItem(at: rootURL.appending(path: "stable"))
        try Data([1]).write(to: rootURL.appending(path: "stable"))
        try await scanner.reconcile(root, change: FileIndexChange(eventID: 22, shallowDirectories: [""]), store: store)
        #expect(Set(try await store.files(root: root.id).map(\.path)) == ["stable", "top.txt"])
        try FileManager.default.removeItem(at: rootURL.appending(path: "stable"))
        try await scanner.reconcile(root, change: FileIndexChange(eventID: 23, shallowDirectories: [""]), store: store)
        #expect(try await store.files(root: root.id).map(\.path) == ["top.txt"])
        // The same replacement must work before the first durable snapshot exists.
        try FileManager.default.createDirectory(at: rootURL.appending(path: "new"), withIntermediateDirectories: true)
        try Data([1]).write(to: rootURL.appending(path: "new/child"))
        let fresh = FileIndexStore(url: folder.appending(path: "fresh-index"))
        _ = try await scanner.scan(root, store: fresh)
        try FileManager.default.removeItem(at: rootURL.appending(path: "new"))
        try Data([1]).write(to: rootURL.appending(path: "new"))
        _ = try await scanner.scan(root, recursive: false, store: fresh)
        #expect(Set(try await fresh.files(root: root.id).map(\.path)) == ["new", "top.txt"])
    }

}
