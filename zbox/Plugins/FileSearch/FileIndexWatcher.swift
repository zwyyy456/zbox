import Foundation
import CoreServices

nonisolated struct FileIndexChange: Sendable {
    var directories: Set<String> = []
    var eventID: UInt64 = 0

    mutating func merge(_ other: Self) {
        directories.formUnion(other.directories)
        eventID = max(eventID, other.eventID)
        if directories.contains("") { directories = [""] }
    }

    var minimalDirectories: [String] {
        directories.sorted().filter { path in
            !directories.contains { $0 != path && ($0.isEmpty || path.hasPrefix($0 + "/")) }
        }
    }
}

@MainActor final class FileIndexWatcher {
    private var stream: FSEventStreamRef?
    private let root: FileSearchRoot
    private let onChange: (FileIndexChange) -> Void

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
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        self.stream = nil
        FSEventStreamRelease(stream)
    }

    private func receive(paths: [String], flags: [FSEventStreamEventFlags], ids: [FSEventStreamEventId]) {
        var change = FileIndexChange()
        let rescanFlags = UInt32(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped |
            kFSEventStreamEventFlagKernelDropped | kFSEventStreamEventFlagEventIdsWrapped |
            kFSEventStreamEventFlagRootChanged | kFSEventStreamEventFlagMount | kFSEventStreamEventFlagUnmount)
        for index in paths.indices {
            change.eventID = max(change.eventID, ids[index])
            if flags[index] & rescanFlags != 0 { change.directories = [""]; break }
            if flags[index] & UInt32(kFSEventStreamEventFlagHistoryDone) != 0 { continue }
            let url = URL(fileURLWithPath: paths[index]).standardizedFileURL
            if FileSearchRoot.contains(url, in: FileSearchRoot.privateDataDirectory) { continue }
            guard FileSearchRoot.contains(url, in: root.url) else { continue }
            let relative = String(url.path.dropFirst(root.url.path == "/" ? 1 : root.url.path.count + 1))
            if root.exclusions.contains(where: { relative == $0 || relative.hasPrefix($0 + "/") }) { continue }
            if !root.includesHidden && relative.split(separator: "/").contains(where: { $0.hasPrefix(".") }) { continue }
            let parent = url.deletingLastPathComponent()
            if url.path == root.url.path || parent.path == root.url.path { change.directories.insert("") }
            else if FileSearchRoot.contains(parent, in: root.url) {
                change.directories.insert(String(parent.path.dropFirst(root.url.path == "/" ? 1 : root.url.path.count + 1)))
            }
        }
        if !change.directories.isEmpty { onChange(change) }
    }
}
