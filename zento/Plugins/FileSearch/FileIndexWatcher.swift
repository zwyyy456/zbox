import Foundation
import CoreServices
import Darwin

nonisolated struct FileIndexChange: Sendable {
    var directories: Set<String> = []
    var eventID: UInt64 = 0
    var shallowDirectories: Set<String> = []

    mutating func merge(_ other: Self) {
        directories.formUnion(other.directories)
        shallowDirectories.formUnion(other.shallowDirectories)
        eventID = max(eventID, other.eventID)
        if directories.contains("") { directories = [""] }
    }

    var minimalDirectories: [String] {
        directories.sorted().filter { path in
            !directories.contains { $0 != path && ($0.isEmpty || path.hasPrefix($0 + "/")) }
        }
    }
    var minimalShallowDirectories: [String] {
        shallowDirectories.sorted().filter { path in
            !directories.contains { $0.isEmpty || path == $0 || path.hasPrefix($0 + "/") }
        }
    }

}

@MainActor final class FileIndexWatcher {
    private var stream: FSEventStreamRef?
    private let root: FileSearchRoot
    private let onChange: (FileIndexChange) -> Void
    private var historyComplete = false
    private var historyWaiter: CheckedContinuation<Void, any Error>?

    static func journalID(for root: FileSearchRoot) throws -> String {
        var info = stat()
        guard stat(root.url.path, &info) == 0 else { throw FileSearchError.unavailable }
        guard let uuid = FSEventsCopyUUIDForDevice(info.st_dev) else { return "" }
        return CFUUIDCreateString(nil, uuid) as String
    }

    func waitForHistory() async throws {
        try Task.checkCancellation()
        guard stream != nil else { throw CancellationError() }
        if historyComplete { return }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { historyWaiter = $0 }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancelHistoryWait() }
        }
        try Task.checkCancellation()
    }

    private func cancelHistoryWait() {
        historyWaiter?.resume(throwing: CancellationError())
        historyWaiter = nil
    }

    init(root: FileSearchRoot, since eventID: UInt64, onChange: @escaping (FileIndexChange) -> Void) throws {
        self.root = root
        self.onChange = onChange
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: { info in
            guard let info else { return nil }
            _ = Unmanaged<FileIndexWatcher>.fromOpaque(info).retain()
            return info
        }, release: { info in
            guard let info else { return }
            Unmanaged<FileIndexWatcher>.fromOpaque(info).release()
        }, copyDescription: nil)
        let flags = UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot)
        guard let stream = FSEventStreamCreate(nil, { _, info, count, eventPaths, flags, ids in
            guard let info else { return }
            let watcher = Unmanaged<FileIndexWatcher>.fromOpaque(info).takeUnretainedValue()
            let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as! [String]
            MainActor.assumeIsolated {
                watcher.receive(paths: paths, flags: Array(UnsafeBufferPointer(start: flags, count: count)),
                    ids: Array(UnsafeBufferPointer(start: ids, count: count)))
            }
        }, &context, [root.url.path] as CFArray, eventID, 0.5, flags) else { throw FileSearchError.watcherFailed }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, .main)
        guard FSEventStreamStart(stream) else { stop(); throw FileSearchError.watcherFailed }
    }

    isolated deinit { stop() }

    func stop() {
        cancelHistoryWait()
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        self.stream = nil
        FSEventStreamRelease(stream)
    }

    private func receive(paths: [String], flags: [FSEventStreamEventFlags], ids: [FSEventStreamEventId]) {
        let batch = FileIndexEventBatch(root: root, paths: paths, flags: flags, ids: ids)
        let change = batch.change
        if !change.directories.isEmpty || !change.shallowDirectories.isEmpty { onChange(change) }
        if batch.historyComplete {
            historyComplete = true
            historyWaiter?.resume()
            historyWaiter = nil
        }
    }
}

/// Pure interpretation of the OS event batch, shared by live updates and startup replay.
nonisolated struct FileIndexEventBatch {
    let change: FileIndexChange
    let historyComplete: Bool
    init(root: FileSearchRoot, paths: [String], flags: [FSEventStreamEventFlags], ids: [FSEventStreamEventId]) {
        var change = FileIndexChange()
        let rescanFlags = UInt32(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped |
            kFSEventStreamEventFlagKernelDropped | kFSEventStreamEventFlagEventIdsWrapped |
            kFSEventStreamEventFlagRootChanged | kFSEventStreamEventFlagMount | kFSEventStreamEventFlagUnmount)
        for index in paths.indices {
            if flags[index] & UInt32(kFSEventStreamEventFlagHistoryDone) == 0 { change.eventID = max(change.eventID, ids[index]) }
            if flags[index] & rescanFlags != 0 { change.directories = [""]; break }
            if flags[index] & UInt32(kFSEventStreamEventFlagHistoryDone) != 0 { continue }
            let url = URL(fileURLWithPath: paths[index]).standardizedFileURL
            if FileSearchRoot.contains(url, in: FileSearchRoot.privateDataDirectory) { continue }
            guard FileSearchRoot.contains(url, in: root.url) else { continue }
            let relative = String(url.path.dropFirst(root.url.path == "/" ? 1 : root.url.path.count + 1))
            if root.exclusions.contains(where: { relative == $0 || relative.hasPrefix($0 + "/") }) { continue }
            if !root.includesHidden && relative.split(separator: "/").contains(where: { $0.hasPrefix(".") }) { continue }
            let parent = url.deletingLastPathComponent()
            let structural = UInt32(kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemRemoved | kFSEventStreamEventFlagItemRenamed)
            if flags[index] & UInt32(kFSEventStreamEventFlagItemIsDir) != 0, flags[index] & structural != 0 {
                change.directories.insert(relative)
            }
            if url.path == root.url.path || parent.path == root.url.path { change.shallowDirectories.insert("") }
            else if FileSearchRoot.contains(parent, in: root.url) {
                change.shallowDirectories.insert(String(parent.path.dropFirst(root.url.path == "/" ? 1 : root.url.path.count + 1)))
            }
        }
        self.change = change
        historyComplete = flags.contains { $0 & UInt32(kFSEventStreamEventFlagHistoryDone) != 0 }
    }
}
