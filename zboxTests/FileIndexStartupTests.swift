import Foundation
import CoreServices
import Testing
@testable import zbox

struct FileIndexStartupTests {
    @Test func replayRequiresMatchingRootRulesAndJournal() async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = FileSearchRoot(url: URL(fileURLWithPath: "/Selected"), volumeID: "volume", fileID: 12)
        let store = FileIndexStore(url: directory)
        #expect(try await store.prepare(root, journalID: "journal-a") == nil)
        let file = IndexedFile(rootID: root.id, path: "kept.txt", name: "kept.txt", isDirectory: false, size: 1, modified: .distantPast)
        try await store.upsert([file], generation: UUID())
        try await store.setCursor(100, root: root.id, persist: true)
        let restored = FileIndexStore(url: directory)
        #expect(try await restored.prepare(root, journalID: "journal-a") == 100)
        #expect(try await restored.files(root: root.id) == [file])
        // An idle replay can advance in memory without rewriting all records.
        try await restored.setCursor(101, root: root.id)
        let reopened = FileIndexStore(url: directory)
        #expect(try await reopened.prepare(root, journalID: "journal-a") == 100)
        var changed = root
        changed.includesHidden = true
        #expect(try await restored.prepare(changed, journalID: "journal-a") == nil)
        #expect(try await reopened.prepare(root, journalID: "journal-b") == nil)
        let unavailableJournal = FileIndexStore(url: directory)
        #expect(try await unavailableJournal.prepare(root, journalID: "") == nil)
    }

    @Test func historyBarrierDoesNotHideDroppedEventsOrInterpretSentinelPath() {
        let root = FileSearchRoot(url: URL(fileURLWithPath: "/Selected"), volumeID: "volume", fileID: 1)
        let batch = FileIndexEventBatch(root: root, paths: ["/Selected/changed/file.txt", "/ignored-sentinel"],
            flags: [UInt32(kFSEventStreamEventFlagItemModified), UInt32(kFSEventStreamEventFlagHistoryDone)], ids: [11, 99])
        #expect(batch.historyComplete)
        #expect(batch.change.directories.isEmpty)
        #expect(batch.change.shallowDirectories == ["changed"])
        #expect(batch.change.eventID == 11)
        let moved = FileIndexEventBatch(root: root, paths: ["/Selected/moved"],
            flags: [UInt32(kFSEventStreamEventFlagItemIsDir | kFSEventStreamEventFlagItemRenamed)], ids: [12])
        #expect(moved.change.directories == ["moved"])
        #expect(moved.change.shallowDirectories == [""])
        #expect(moved.change.minimalShallowDirectories == [""])
        for flag in [kFSEventStreamEventFlagUserDropped, kFSEventStreamEventFlagKernelDropped,
                     kFSEventStreamEventFlagMustScanSubDirs, kFSEventStreamEventFlagEventIdsWrapped,
                     kFSEventStreamEventFlagRootChanged] {
            let lost = FileIndexEventBatch(root: root, paths: ["/Selected", ""],
                flags: [UInt32(flag), UInt32(kFSEventStreamEventFlagHistoryDone)], ids: [12, 99])
            #expect(lost.historyComplete)
            #expect(lost.change.directories == [""])
        }
        let idle = FileIndexEventBatch(root: root, paths: [""], flags: [UInt32(kFSEventStreamEventFlagHistoryDone)], ids: [99])
        #expect(idle.historyComplete)
        #expect(idle.change.directories.isEmpty)
    }

    @Test(.timeLimit(.minutes(1))) @MainActor
    func realHistoryBarrierAndStoppedStreamFinishTheirWaiters() async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = try FileSearchRoot.selected(directory)
        let watcher = try FileIndexWatcher(root: root, since: FSEventsGetCurrentEventId()) { _ in }
        defer { watcher.stop() }
        try await watcher.waitForHistory()
        // Completion remains observable even when HistoryDone arrived before the await.
        try await watcher.waitForHistory()
        let stopped = try FileIndexWatcher(root: root, since: FSEventsGetCurrentEventId()) { _ in }
        stopped.stop()
        await #expect(throws: CancellationError.self) { try await stopped.waitForHistory() }
    }
    @Test(.timeLimit(.minutes(1))) @MainActor
    func replaysRealEventsSinceTheSavedSnapshot() async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        let rootURL = directory.appending(path: "root")
        try FileManager.default.createDirectory(at: rootURL.appending(path: "changed"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = rootURL.appending(path: "changed/file.txt")
        try Data([1]).write(to: target)
        let root = try FileSearchRoot.selected(rootURL)
        let storeURL = directory.appending(path: "index")
        let store = FileIndexStore(url: storeURL), scanner = FileIndexScanner()
        let journal = try FileIndexWatcher.journalID(for: root)
        _ = try await store.prepare(root, journalID: journal)
        let baseline = FSEventsGetCurrentEventId()
        let (events, continuation) = AsyncStream<FileIndexChange>.makeStream()
        let observer = try FileIndexWatcher(root: root, since: baseline) { continuation.yield($0) }
        defer { observer.stop(); continuation.finish() }
        _ = try await scanner.scan(root, store: store)
        try await store.setCursor(baseline, root: root.id, persist: true)
        try await observer.waitForHistory()
        try Data([1, 2, 3, 4]).write(to: target)
        // Observe delivery without applying it, then restart from the older on-disk cursor.
        for await change in events {
            if change.shallowDirectories.contains("changed") || change.directories.contains("changed") { break }
            try Task.checkCancellation()
        }
        try Task.checkCancellation()
        observer.stop()
        let restored = FileIndexStore(url: storeURL)
        let cursor = try #require(await restored.prepare(root, journalID: journal))
        var pending = FileIndexChange()
        let replay = try FileIndexWatcher(root: root, since: cursor) { pending.merge($0) }
        defer { replay.stop() }
        try await replay.waitForHistory()
        #expect(!pending.directories.isEmpty || !pending.shallowDirectories.isEmpty)
        try await scanner.reconcile(root, change: pending, store: restored)
        #expect(try await restored.files(root: root.id).first { $0.path == "changed/file.txt" }?.size == 4)
    }

}
