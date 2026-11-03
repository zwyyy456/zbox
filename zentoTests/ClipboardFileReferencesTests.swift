import AppKit
import Testing
@testable import zento

@MainActor
struct ClipboardFileReferencesTests {
    @Test func capturesPersistsAndRestoresMixedFileReferences() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("file # 中文.txt")
        let folder = root.appendingPathComponent("folder", isDirectory: true)
        try Data("original".utf8).write(to: file)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        #expect(board.writeObjects([file as NSURL, folder as NSURL]))
        let payload = try #require(try ClipboardReader.read(from: board, excluding: [], sourceBundleID: "test.source"))
        #expect(payload.kind == "files")
        #expect(try ClipboardFileReferences.decode(payload.data).map(\.path) == [file.path, folder.path])
        let storeURL = root.appendingPathComponent("history.store")
        var store: ClipboardHistoryStore? = try ClipboardHistoryStore(url: storeURL)
        try store?.add(payload)
        try store?.add(payload)
        store = nil
        let reopened = try ClipboardHistoryStore(url: storeURL)
        let entries = try reopened.entries(query: "中文", filter: .files)
        #expect(entries.count == 1)
        let entry = try #require(entries.first)
        #expect(entry.fileURLs.map(\.path) == [file.path, folder.path])
        #expect(entry.byteCount == payload.data.count)
        #expect(try reopened.entries(filter: .text).isEmpty)
        let restored = try #require(try reopened.payload(for: entry.id))
        // A reference uses the current file, rather than a snapshot of its bytes.
        try Data("changed".utf8).write(to: file)
        let access = ClipboardAccessCoordinator()
        try ClipboardWriter.write(restored, to: board, coordinator: access)
        let urls = try #require(board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL])
        #expect(urls.map(\.path) == [file.path, folder.path])
        #expect(try Data(contentsOf: urls[0]) == Data("changed".utf8))
        #expect(access.ignoredChangeCount == board.changeCount)
        try FileManager.default.removeItem(at: file)
        board.clearContents()
        board.setString("preserve", forType: .string)
        let count = board.changeCount
        #expect(throws: ClipboardHistoryError.fileUnavailable) {
            try ClipboardWriter.write(restored, to: board, coordinator: access)
        }
        #expect(board.changeCount == count)
        #expect(board.string(forType: .string) == "preserve")
    }

    @Test func singleDirectoryAndInvalidMixedItems() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let directory = FileManager.default.temporaryDirectory
        board.writeObjects([directory as NSURL])
        let payload = try #require(try ClipboardReader.read(from: board, excluding: [], sourceBundleID: nil))
        #expect(try ClipboardFileReferences.decode(payload.data).map(\.path) == [directory.path])
        #expect(try ClipboardReader.read(from: board, excluding: ["excluded"], sourceBundleID: "excluded") == nil)
        board.setData(Data(), forType: .init("org.nspasteboard.ConcealedType"))
        #expect(try ClipboardReader.read(from: board, excluding: [], sourceBundleID: nil) == nil)
        board.clearContents()
        let file = NSPasteboardItem(); file.setString(directory.absoluteString, forType: .fileURL)
        let text = NSPasteboardItem(); text.setString("not a file", forType: .string)
        board.writeObjects([file, text])
        #expect(throws: ClipboardHistoryError.unsupported) {
            _ = try ClipboardReader.read(from: board, excluding: [], sourceBundleID: nil)
        }
        #expect(throws: ClipboardHistoryError.unsupported) {
            _ = try ClipboardFileReferences.encode([URL(string: "https://example.com")!])
        }
    }
}
