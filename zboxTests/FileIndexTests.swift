import Foundation
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
        let store = FileIndexStore(url: folder.appending(path: "index.sqlite"))
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

    @Test func unfinishedScanDoesNotPruneSavedRecords() async throws {
        let url = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let root = UUID()
        let store = FileIndexStore(url: url.appending(path: "index.sqlite"))
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
        let store = FileIndexStore(url: folder.appending(path: "index.sqlite"))
        let scanner = FileIndexScanner()
        _ = try await scanner.scan(root, store: store)
        _ = try await scanner.scan(root, directory: "Example.app/Contents", store: store)
        _ = try await scanner.scan(root, directory: "alias/nested", store: store)
        #expect(Set(try await store.files(root: root.id).map(\.path)) == ["Example.app", "alias"])
    }

}
