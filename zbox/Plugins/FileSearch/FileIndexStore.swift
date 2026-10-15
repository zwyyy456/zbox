import Foundation
import Darwin

nonisolated struct IndexedFile: Identifiable, Sendable, Equatable {
    let rootID: UUID
    let path: String
    let name: String
    let isDirectory: Bool
    let size: Int64
    let modified: Date
    var id: String { rootID.uuidString + "/" + path }
    var fileExtension: String { (name as NSString).pathExtension.lowercased() }
    static func normalized(_ value: String) -> String {
        if value.utf8.allSatisfy({ $0 < 128 && !($0 >= 65 && $0 <= 90) }) { return value }
        return value.precomposedStringWithCanonicalMapping.lowercased()
    }
}

nonisolated struct FileIndexConfiguration: Codable, Equatable, Sendable {
    let root: FileSearchRoot
    let journalID: String
}

/// SQLite is deliberately not migrated: this directory contains only rebuildable snapshots.
actor FileIndexStore {
    let url: URL
    init(url: URL = URL.applicationSupportDirectory.appending(path: "zbox/file-search-index")) { self.url = url }

    private struct Change: Sendable {
        var file: IndexedFile?
        var generation: UUID
        var revision: UInt64
        var replacesDirectory = false
    }
    /// Paths live once in the hash table. Chunk records store scalar metadata and
    /// name offsets into a UTF-8 arena; the root identity is shared by all entries.
    private struct Changes: Sendable {
        struct Entry: Sendable {
            var generation: UUID
            var revision: UInt64
            var size: Int64
            var modified: Double
            var nameOffset: UInt32
            var nameLength: UInt32
            var deleted: Bool
            var isDirectory: Bool
            var replacesDirectory: Bool
        }
        private struct Chunk: Sendable {
            var entries: [Entry] = []
            var names: [UInt8] = []
            init() { entries.reserveCapacity(chunkSize) }
        }
        private var positions: [String: Int] = [:]
        private var chunks: [Chunk] = []
        private var rootID: UUID?
        private static let chunkSize = 4096
        var count: Int { positions.count }
        var isEmpty: Bool { positions.isEmpty }
        var keys: Dictionary<String, Int>.Keys { positions.keys }
        var values: some Sequence<Change> { positions.keys.lazy.map { self[$0]! } }
        func contains(_ path: String) -> Bool { positions[path] != nil }
        func entry(_ path: String) -> Entry? {
            guard let position = positions[path] else { return nil }
            return chunks[position / Self.chunkSize].entries[position % Self.chunkSize]
        }
        func containsFile(_ path: String) -> Bool { entry(path)?.deleted == false }
        subscript(path: String) -> Change? {
            get {
                guard let position = positions[path] else { return nil }
                let chunk = chunks[position / Self.chunkSize]
                let entry = chunk.entries[position % Self.chunkSize]
                let start = Int(entry.nameOffset), end = start + Int(entry.nameLength)
                let file = entry.deleted ? nil : IndexedFile(rootID: rootID!, path: path,
                    name: String(decoding: chunk.names[start..<end], as: UTF8.self),
                    isDirectory: entry.isDirectory, size: entry.size,
                    modified: Date(timeIntervalSinceReferenceDate: entry.modified))
                return Change(file: file, generation: entry.generation, revision: entry.revision,
                    replacesDirectory: entry.replacesDirectory)
            }
            set {
                guard let value = newValue else { preconditionFailure("Use compaction to remove overlay entries") }
                let position = positions[path] ?? positions.count
                let chunkID = position / Self.chunkSize, slot = position % Self.chunkSize
                if chunkID == chunks.count { chunks.append(Chunk()) }
                var offset: UInt32 = 0, length: UInt32 = 0
                if let file = value.file {
                    rootID = file.rootID
                    if slot < chunks[chunkID].entries.count {
                        let old = chunks[chunkID].entries[slot]
                        let start = Int(old.nameOffset), end = start + Int(old.nameLength)
                        if chunks[chunkID].names[start..<end].elementsEqual(file.name.utf8) {
                            offset = old.nameOffset; length = old.nameLength
                        } else {
                            offset = UInt32(chunks[chunkID].names.count); length = UInt32(file.name.utf8.count)
                            chunks[chunkID].names.append(contentsOf: file.name.utf8)
                        }
                    } else {
                        offset = UInt32(chunks[chunkID].names.count); length = UInt32(file.name.utf8.count)
                        chunks[chunkID].names.append(contentsOf: file.name.utf8)
                    }
                }
                let entry = Entry(generation: value.generation, revision: value.revision,
                    size: value.file?.size ?? 0, modified: value.file?.modified.timeIntervalSinceReferenceDate ?? 0,
                    nameOffset: offset, nameLength: length, deleted: value.file == nil,
                    isDirectory: value.file?.isDirectory ?? false, replacesDirectory: value.replacesDirectory)
                if slot < chunks[chunkID].entries.count { chunks[chunkID].entries[slot] = entry }
                else { positions[path] = position; chunks[chunkID].entries.append(entry) }
            }
        }
        func keeping(after revision: UInt64) -> Self {
            var result = Self()
            for (path, position) in positions {
                if chunks[position / Self.chunkSize].entries[position % Self.chunkSize].revision > revision {
                    result[path] = self[path]
                }
            }
            return result
        }
    }

    private final class RootState {
        var base: FileMappedIndex?
        var changes = Changes()
        var revision: UInt64 = 0
        var cursor: UInt64?
        var lastSave = Date.distantPast
        var compacting = false
        var configuration: FileIndexConfiguration?
        init(base: FileMappedIndex?) {
            self.base = base; cursor = base?.cursor
            if base != nil { lastSave = Date() }
            configuration = base.flatMap { try? JSONDecoder().decode(FileIndexConfiguration.self, from: $0.metadata) }
        }
    }
    private var states: [UUID: RootState] = [:]

    private func snapshotURL(_ root: UUID) -> URL { url.appending(path: root.uuidString + ".index") }
    private func state(_ root: UUID) throws -> RootState {
        try Task.checkCancellation()
        if let state = states[root] { return state }
        let file = snapshotURL(root)
        var base: FileMappedIndex?
        if FileManager.default.fileExists(atPath: file.path) {
            do { base = try FileMappedIndex(url: file) }
            catch FileMappedIndex.FormatError.invalid {
                // The caller starts a full scan when there is no durable event cursor.
                // Keep the old file until a complete replacement can be atomically installed.
                base = nil
            }
        }
        let state = RootState(base: base)
        states[root] = state
        return state
    }

    /// A replay cursor is usable only for the same filesystem identity, rules and event journal.
    func prepare(_ root: FileSearchRoot, journalID: String) throws -> UInt64? {
        let current = try state(root.id)
        let configuration = FileIndexConfiguration(root: root, journalID: journalID)
        if journalID.isEmpty || current.configuration != configuration {
            let replacement = RootState(base: nil)
            replacement.configuration = configuration
            states[root.id] = replacement
            return nil
        }
        return current.cursor
    }

    func upsert(_ files: [IndexedFile], generation: UUID) throws {
        for file in files {
            let state = try state(file.rootID)
            state.revision += 1
            let previous = state.changes.entry(file.path)
            let replacesDirectory = !file.isDirectory && ((previous?.deleted == false && previous?.isDirectory == true) || previous?.replacesDirectory == true)
            state.changes[file.path] = Change(file: file, generation: generation, revision: state.revision, replacesDirectory: replacesDirectory)
        }
    }

    func finishScan(root: UUID, directory: String, generation: UUID, recursive: Bool = true) throws {
        let state = try state(root)
        func inScope(_ path: String) -> Bool {
            if recursive { return directory.isEmpty || path == directory || path.hasPrefix(directory + "/") }
            let parent = path.lastIndex(of: "/").map { String(path[..<$0]) } ?? ""
            return path == directory || parent == directory
        }
        var stale: [String] = []
        var replacedDirectories: [String] = []
        if let base = state.base {
            if recursive {
                for range in try base.indices(in: directory) {
                    for i in range {
                        if i % 256 == 0 { try Task.checkCancellation() }
                        let path = try base.path(i)
                        if state.changes.entry(path)?.generation != generation { stale.append(path) }
                    }
                }
            } else {
                for i in try base.directEntries(in: directory) {
                    try Task.checkCancellation()
                    let path = try base.path(i)
                    if state.changes.entry(path)?.generation != generation { stale.append(path) }
                    else if base.isDirectory(i), state.changes.entry(path)?.isDirectory == false { replacedDirectories.append(path) }
                }
            }
        }
        for path in state.changes.keys {
            try Task.checkCancellation()
            if let change = state.changes.entry(path), !change.deleted, inScope(path) {
                if change.generation != generation { stale.append(path) }
                else if !recursive, change.replacesDirectory { replacedDirectories.append(path) }
            }
        }
        if !recursive {
            // A vanished immediate child may have owned an indexed subtree.
            let vanished = stale
            if let base = state.base {
                for path in vanished {
                    for range in try base.indices(in: path) {
                        for i in range { stale.append(try base.path(i)) }
                    }
                }
            }
            for path in state.changes.keys where vanished.contains(where: { path.hasPrefix($0 + "/") }) { stale.append(path) }
        }
        for directory in replacedDirectories {
            if let base = state.base {
                for range in try base.indices(in: directory) {
                    for i in range {
                        let path = try base.path(i)
                        if path != directory { stale.append(path) }
                    }
                }
            }
            for path in state.changes.keys where path.hasPrefix(directory + "/") { stale.append(path) }
        }
        try Task.checkCancellation()
        for path in stale {
            try Task.checkCancellation()
            state.revision += 1
            state.changes[path] = Change(file: nil, generation: generation, revision: state.revision)
        }
    }

    func cursor(root: UUID) throws -> UInt64? { try state(root).cursor }

    /// The cursor on disk is written WITH the snapshot, never ahead of its contents.
    /// Small batches remain in memory; a restart replays from the last durable cursor.
    func setCursor(_ event: UInt64, root: UUID, persist: Bool = false) async throws {
        let state = try state(root)
        state.cursor = event
        guard persist || !state.changes.isEmpty else { return }
        guard !state.compacting,
              persist || state.base == nil || state.changes.count >= 4096 || Date().timeIntervalSince(state.lastSave) >= 30 else { return }
        let revision = state.revision
        let base = state.base, changes = state.changes
        state.compacting = true
        defer { state.compacting = false }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let destination = snapshotURL(root)
        let temporary = url.appending(path: "." + root.uuidString + "." + UUID().uuidString + ".building")
        let metadata = try state.configuration.map { try JSONEncoder().encode($0) } ?? Data()
        defer { try? FileManager.default.removeItem(at: temporary) }
        let encoding = Task.detached(priority: .utility) {
            // Keep references to mapped entries and overlay keys, not a second full file array.
            var original: [Int] = []
            if let base {
                original.reserveCapacity(base.count)
                for i in 0..<base.count {
                    if i % 256 == 0 { try Task.checkCancellation() }
                    if !changes.contains(try base.path(i)) { original.append(i) }
                }
            }
            let added = changes.keys.filter { changes.containsFile($0) }
            try FileMappedIndex.write(count: original.count + added.count, fileAt: { position in
                if position < original.count { return try base!.file(original[position], root: root) }
                return changes[added[position - original.count]]!.file!
            }, cursor: event, metadata: metadata, to: temporary)
            return try FileMappedIndex(url: temporary)
        }
        let replacement = try await withTaskCancellationHandler {
            try await encoding.value
        } onCancel: { encoding.cancel() }
        try Task.checkCancellation()
        guard states[root] === state else { return }
        guard rename(temporary.path, destination.path) == 0 else { throw FileSearchError.storage }
        state.base = replacement
        state.changes = state.changes.keeping(after: revision)
        state.lastSave = Date()
    }

    func remove(root: UUID) throws {
        try Task.checkCancellation()
        let file = snapshotURL(root)
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
        states[root] = nil
    }

    func releaseMemory() { states = [:] }

    func clear() throws {
        try Task.checkCancellation()
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        states = [:]
    }

    func files(root: UUID) throws -> [IndexedFile] {
        let state = try state(root)
        return try Self.collectFiles(root: root, base: state.base, changes: state.changes).sorted { $0.path < $1.path }
    }

    private nonisolated static func collectFiles(root: UUID, base: FileMappedIndex?, changes: Changes) throws -> [IndexedFile] {
        var result: [IndexedFile] = []
        if let base {
            for i in 0..<base.count {
                if i % 256 == 0 { try Task.checkCancellation() }
                if !changes.contains(try base.path(i)) { result.append(try base.file(i, root: root)) }
            }
        }
        result.append(contentsOf: changes.values.compactMap(\.file))
        return result
    }

    private struct SearchSnapshot: Sendable {
        let root: FileSearchRoot
        let base: FileMappedIndex?
        let changes: Changes
    }

    func search(_ query: FileSearchQuery, roots: [FileSearchRoot], sort: FileSearchSort, limit: Int = 200) async throws -> FileSearchPage {
        try Task.checkCancellation()
        guard !query.isEmpty, limit > 0 else { return FileSearchPage() }
        let snapshots = try roots.map { root in
            let state = try state(root.id)
            return SearchSnapshot(root: root, base: state.base, changes: state.changes)
        }
        let worker = Task.detached(priority: .userInitiated) {
            try Self.search(query, snapshots: snapshots, sort: sort, limit: limit)
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: { worker.cancel() }
    }

    private nonisolated static func search(_ query: FileSearchQuery, snapshots: [SearchSnapshot], sort: FileSearchSort, limit: Int) throws -> FileSearchPage {
        try Task.checkCancellation()
        var best = FileSearchTopResults(limit: limit, sort: sort)
        // Non-ASCII names with a selective ASCII suffix (e.g. a document number)
        // should not all be decoded just because they share the same character mask.
        let asciiFragments = query.names.flatMap { term in
            term.utf8.split(whereSeparator: { $0 >= 128 }).filter { !$0.isEmpty }.map(Array.init)
        }
        let mask = query.names.reduce(UInt64(0)) { $0 | FileMappedIndex.mask($1) }
        for state in snapshots {
            let root = state.root
            if let base = state.base {
                let paths = try query.paths.isEmpty ? nil : FileIndexPathCandidates(index: base, terms: query.paths, root: root)
                var filters = query
                if paths != nil { filters.paths = [] }
                for group in try base.nameGroups(phrase: query.names.joined(separator: " "), sort: sort) {
                    guard best.canImprove(name: "", score: group.score) else { continue }
                    let positions: Range<Int>
                    if let paths {
                        let start = paths.names.partitioningIndex { $0 >= group.range.lowerBound }
                        let end = paths.names.partitioningIndex { $0 >= group.range.upperBound }
                        positions = start..<end
                    } else { positions = group.range }
                    for position in positions {
                        let id = paths.map { $0.names[position] } ?? position
                        if id % 64 == 0 { try Task.checkCancellation() }
                        guard base.nameMask(id) & mask == mask else { continue }
                        guard asciiFragments.isEmpty || base.containsASCIIFragments(asciiFragments, name: id) else { continue }
                        let normalized = try base.normalizedName(id)
                        // Names are sorted within each rank group; the remaining suffix cannot win.
                        guard best.canImprove(name: normalized, score: group.score) else { break }
                        guard let score = query.nameScore(normalized), best.canImprove(name: normalized, score: score) else { continue }
                        let name = try base.name(id)
                        for posting in base.postings(id) {
                            try Task.checkCancellation()
                            let entry = base.entry(at: posting)
                            if let paths, !paths.contains(entry) { continue }
                            guard try state.changes.isEmpty || !state.changes.contains(base.path(entry)) else { continue }
                            let file = try base.file(entry, root: root.id, name: name)
                            if filters.matchesFilters(file, root: root) {
                                best.insert(file, score: score, normalizedName: normalized, root: root)
                            }
                        }
                    }
                }
            }
            for change in state.changes.values {
                try Task.checkCancellation()
                guard let file = change.file, let score = query.score(file, root: root) else { continue }
                best.insert(file, score: score, normalizedName: IndexedFile.normalized(file.name), root: root)
            }
        }
        return best.page
    }
}

/// Worst-first heap: ranking all hits costs O(matches * log(limit)), with one final sort.
private nonisolated struct FileSearchTopResults {
    struct Hit {
        let file: IndexedFile
        let score: Int
        let name: String
        let path: String
    }
    let limit: Int
    let sort: FileSearchSort
    var heap: [Hit] = []
    var matches = 0
    func precedes(_ a: Hit, _ b: Hit) -> Bool {
        if sort == .relevance, a.score != b.score { return a.score > b.score }
        if sort == .modified, a.file.modified != b.file.modified { return a.file.modified > b.file.modified }
        return a.name == b.name ? a.path < b.path : a.name < b.name
    }
    func canImprove(name: String, score: Int) -> Bool {
        // Once truncation is proven, worse names cannot affect either the page or hasMore.
        guard heap.count == limit, matches > limit, sort != .modified else { return true }
        let worst = heap[0]
        if sort == .relevance, score != worst.score { return score > worst.score }
        return name <= worst.name
    }

    mutating func insert(_ file: IndexedFile, score: Int, normalizedName: String, root: FileSearchRoot) {
        matches += 1
        let hit = Hit(file: file, score: score, name: normalizedName, path: root.url.appending(path: file.path).path)
        if heap.count < limit {
            heap.append(hit)
            var i = heap.count - 1
            while i > 0 {
                let parent = (i - 1) / 2
                guard precedes(heap[parent], heap[i]) else { break }
                heap.swapAt(parent, i); i = parent
            }
        } else if precedes(hit, heap[0]) {
            heap[0] = hit
            var i = 0
            while i * 2 + 1 < heap.count {
                var child = i * 2 + 1
                if child + 1 < heap.count, precedes(heap[child], heap[child + 1]) { child += 1 }
                guard precedes(heap[i], heap[child]) else { break }
                heap.swapAt(i, child); i = child
            }
        }
    }
    var page: FileSearchPage { FileSearchPage(files: heap.sorted(by: precedes).map(\.file), hasMore: matches > limit) }
}

private extension Array where Element == Int {
    nonisolated func partitioningIndex(_ predicate: (Int) -> Bool) -> Int {
        var low = 0, high = count
        while low < high {
            let mid = low + (high - low) / 2
            if predicate(self[mid]) { high = mid } else { low = mid + 1 }
        }
        return low
    }
}
