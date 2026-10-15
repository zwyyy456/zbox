import Foundation

/// A disposable, little-endian snapshot. All offsets are relative to the UTF-8 arena.
/// Records are path-sorted; each unique name owns a contiguous posting list.
nonisolated struct FileMappedIndex: Sendable {
    enum FormatError: Error { case invalid }
    private static let magic: UInt64 = 0x31584449465A // ZFIDX1
    private let data: Data
    let count: Int
    let nameCount: Int
    let cursor: UInt64
    private let namesOffset: Int
    private let directoriesOffset: Int
    private let directoryPostingsOffset: Int
    let directoryCount: Int
    let metadata: Data
    private let postingsOffset: Int
    private let stringsOffset: Int

    init(url: URL) throws {
        try self.init(data: Data(contentsOf: url, options: .alwaysMapped))
    }

    private init(data: Data) throws {
        guard data.count >= 64 else { throw FormatError.invalid }
        func word(_ offset: Int) -> UInt64 {
            data.withUnsafeBytes { UInt64(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt64.self)) }
        }
        guard word(0) == Self.magic, word(8) == 5,
              word(24) <= UInt64((data.count - 64) / 56),
              word(32) <= UInt64((data.count - 64) / 72) else { throw FormatError.invalid }
        self.data = data
        cursor = word(16)
        count = Int(word(24))
        nameCount = Int(word(32))
        guard word(40) <= UInt64((data.count - 64) / 32) else { throw FormatError.invalid }
        directoryCount = Int(word(40))
        namesOffset = 64 + count * 40
        directoriesOffset = namesOffset + nameCount * 56
        postingsOffset = directoriesOffset + directoryCount * 32
        directoryPostingsOffset = postingsOffset + count * 8
        stringsOffset = directoryPostingsOffset + count * 8
        guard stringsOffset <= data.count, word(48) <= UInt64(data.count - stringsOffset),
              word(56) == UInt64(data.count - stringsOffset) - word(48) else { throw FormatError.invalid }
        metadata = data.subdata(in: (stringsOffset + Int(word(48)))..<data.count)
        // Validate references without decoding the entire string arena into heap objects.
        func validString(_ offset: Int) -> Bool {
            let start = word(offset), length = word(offset + 8)
            return start <= word(48) && length <= word(48) - start
        }
        for i in 0..<count {
            if i % 1024 == 0 { try Task.checkCancellation() }
            let offset = 64 + i * 40
            guard word(offset) < UInt64(nameCount),
                  word(offset + 24) <= 1, word(offset + 32) < UInt64(directoryCount),
                  Double(bitPattern: word(offset + 16)).isFinite,
                  word(postingsOffset + i * 8) < UInt64(count),
                  word(directoryPostingsOffset + i * 8) < UInt64(count) else { throw FormatError.invalid }
        }
        for i in 0..<directoryCount {
            let offset = directoriesOffset + i * 32
            guard validString(offset), word(offset + 16) <= UInt64(count),
                  word(offset + 24) <= UInt64(count) - word(offset + 16) else { throw FormatError.invalid }
        }
        for i in 0..<nameCount {
            let offset = namesOffset + i * 56
            guard validString(offset), validString(offset + 16),
                  word(offset + 40) <= UInt64(count),
                  word(offset + 48) <= UInt64(count) - word(offset + 40) else { throw FormatError.invalid }
        }
    }

    private func word(_ offset: Int) -> UInt64 {
        data.withUnsafeBytes { UInt64(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt64.self)) }
    }

    private func string(_ offset: Int) throws -> String {
        let start = stringsOffset + Int(word(offset)), end = start + Int(word(offset + 8))
        guard let value = String(bytes: data[start..<end], encoding: .utf8) else { throw FormatError.invalid }
        return value
    }

    static func mask(_ text: String) -> UInt64 {
        // A necessary condition only: collisions retain extra candidates, never drop matches.
        text.utf8.reduce(0) { $0 | (UInt64(1) << ($1 & 63)) }
    }

    func path(_ index: Int) throws -> String {
        let offset = 64 + index * 40
        let parent = try directory(Int(word(offset + 32)))
        let basename = try name(Int(word(offset)))
        return parent.isEmpty ? basename : parent + "/" + basename
    }
    func name(_ id: Int) throws -> String { try string(namesOffset + id * 56) }
    func normalizedName(_ id: Int) throws -> String { try string(namesOffset + id * 56 + 16) }
    func nameMask(_ id: Int) -> UInt64 { word(namesOffset + id * 56 + 32) }
    /// Necessary byte-level condition only; final Unicode matching still decides hits.
    func containsASCIIFragments(_ fragments: [[UInt8]], name id: Int) -> Bool {
        let offset = namesOffset + id * 56 + 16
        let start = stringsOffset + Int(word(offset)), length = Int(word(offset + 8))
        return data.withUnsafeBytes { bytes in
            fragments.allSatisfy { fragment in
                fragment.withUnsafeBytes { needle in
                    memmem(bytes.baseAddress! + start, length, needle.baseAddress!, needle.count) != nil
                }
            }
        }
    }

    func postings(_ id: Int) -> Range<Int> {
        let start = Int(word(namesOffset + id * 56 + 40))
        return start..<(start + Int(word(namesOffset + id * 56 + 48)))
    }
    func entry(at posting: Int) -> Int { Int(word(postingsOffset + posting * 8)) }
    func file(_ index: Int, root: UUID, name: String? = nil) throws -> IndexedFile {
        let offset = 64 + index * 40
        let basename = try name ?? self.name(Int(word(offset)))
        let parent = try directory(Int(word(offset + 32)))
        return IndexedFile(rootID: root, path: parent.isEmpty ? basename : parent + "/" + basename, name: basename,
            isDirectory: word(offset + 24) == 1, size: Int64(bitPattern: word(offset + 8)),
            modified: Date(timeIntervalSinceReferenceDate: Double(bitPattern: word(offset + 16))))
    }

    /// Lexicographic path order makes a directory's descendants a contiguous range.
    /// The directory entry itself is separate (e.g. "docs-other" sorts before "docs/").
    func indices(in directory: String) throws -> [Range<Int>] {
        guard !directory.isEmpty else { return [0..<count] }
        func boundary(_ before: (String) -> Bool) throws -> Int {
            var low = 0, high = count
            while low < high {
                let mid = low + (high - low) / 2
                if try before(path(mid)) { low = mid + 1 } else { high = mid }
            }
            return low
        }
        let exact = try boundary { $0 < directory }
        let prefix = directory + "/"
        let start = try boundary { $0 < prefix }
        let end = try boundary { $0 < prefix || $0.hasPrefix(prefix) }
        var ranges = [start..<end]
        if exact < count, try path(exact) == directory { ranges.append(exact..<(exact + 1)) }
        return ranges
    }

    func directEntries(in directory: String) throws -> [Int] {
        var low = 0, high = directoryCount
        while low < high {
            let mid = low + (high - low) / 2
            if try self.directory(mid) < directory { low = mid + 1 } else { high = mid }
        }
        var entries: [Int] = []
        while low < directoryCount, try self.directory(low) == directory {
            entries.append(contentsOf: directoryEntries(low).map { directoryEntry(at: $0) })
            low += 1
        }
        return entries
    }

    func nameGroups(phrase: String, sort: FileSearchSort) throws -> [(range: Range<Int>, score: Int)] {
        guard sort == .relevance, !phrase.isEmpty else { return [(0..<nameCount, phrase.isEmpty ? 1 : 3)] }
        func boundary(_ before: (String) -> Bool) throws -> Int {
            var low = 0, high = nameCount
            while low < high {
                let mid = low + (high - low) / 2
                if try before(normalizedName(mid)) { low = mid + 1 } else { high = mid }
            }
            return low
        }
        let start = try boundary { $0 < phrase }
        let exactEnd = try boundary { $0 <= phrase }
        let prefixEnd = try boundary { $0 < phrase || $0.hasPrefix(phrase) }
        return [(start..<exactEnd, 3), (exactEnd..<prefixEnd, 2), (0..<start, 1), (prefixEnd..<nameCount, 1)]
    }

    func isDirectory(_ entry: Int) -> Bool { word(64 + entry * 40 + 24) == 1 }
    func nameID(_ entry: Int) -> Int { Int(word(64 + entry * 40)) }
    func directory(_ id: Int) throws -> String { try string(directoriesOffset + id * 32) }
    func directoryEntries(_ id: Int) -> Range<Int> {
        let offset = directoriesOffset + id * 32
        let start = Int(word(offset + 16))
        return start..<(start + Int(word(offset + 24)))
    }
    func directoryEntry(at posting: Int) -> Int { Int(word(directoryPostingsOffset + posting * 8)) }

    /// Stream each section to its final offset. Sorting uses integer references rather than
    /// copies of IndexedFile, and postings use flat arrays rather than one allocation per name.
    static func write(count: Int, fileAt: (Int) throws -> IndexedFile, cursor: UInt64, metadata: Data = Data(), to url: URL) throws {
        var timing = FileIndexBuildTiming()
        guard count >= 0, UInt64(count) <= UInt64(UInt32.max) else { throw FormatError.invalid }
        var rawPaths: [String] = []
        var rawNames: [FileIndexBuildStrings.Span] = [], normalized: [FileIndexBuildStrings.Span] = []
        var arena = FileIndexBuildStrings()
        rawPaths.reserveCapacity(count); rawNames.reserveCapacity(count); normalized.reserveCapacity(count)
        for i in 0..<count {
            if i % 256 == 0 { try Task.checkCancellation() }
            let file = try fileAt(i)
            rawPaths.append(file.path)
            let ascii = file.name.utf8.allSatisfy { $0 < 128 }
            let canonical = ascii ? file.name : file.name.precomposedStringWithCanonicalMapping
            let raw = arena.append(file.name, canonical: canonical)
            rawNames.append(raw)
            let lowercase = canonical.lowercased()
            // If casing did not change the already-NFC bytes (e.g. Chinese),
            // normalization is still valid and need not scan the name again.
            let folded = ascii || lowercase.utf8.elementsEqual(canonical.utf8)
                ? lowercase : lowercase.precomposedStringWithCanonicalMapping
            normalized.append(folded.utf8.elementsEqual(file.name.utf8) ? raw :
                arena.append(folded, canonical: folded))
        }
        timing.mark("collect")
        var paths = (0..<count).map(UInt32.init)
        var comparisons = 0
        func checkSortCancellation() throws {
            comparisons += 1
            if comparisons % 4096 == 0 { try Task.checkCancellation() }
        }
        try paths.sort {
            try checkSortCancellation()
            return rawPaths[Int($0)] < rawPaths[Int($1)]
        }
        var byName = (0..<count).map(UInt32.init)
        try byName.sort { a, b in
            try checkSortCancellation()
            let a = Int(a), b = Int(b)
            let order = arena.compare(normalized[a], normalized[b])
            if order != 0 { return order < 0 }
            let rawOrder = arena.compare(rawNames[a], rawNames[b])
            if rawOrder != 0 { return rawOrder < 0 }
            // Canonically equivalent spellings need separate IDs: paths are rebuilt
            // from the original basename bytes, not from a normalized representative.
            return arena.bytes(in: rawNames[a]).lexicographicallyPrecedes(arena.bytes(in: rawNames[b]))
        }
        timing.mark("sort")
        var nameSources: [UInt32] = [], nameStarts: [UInt32] = []
        var nameIDs = Array(repeating: UInt32(0), count: count)
        var lastName: FileIndexBuildStrings.Span?
        for (position, sourceID) in byName.enumerated() {
            if position % 256 == 0 { try Task.checkCancellation() }
            let source = Int(sourceID), name = rawNames[source]
            if lastName == nil || arena.compare(lastName!, name) != 0 || !arena.bytes(in: lastName!).elementsEqual(arena.bytes(in: name)) {
                nameSources.append(sourceID); nameStarts.append(UInt32(position)); lastName = name
            }
            nameIDs[source] = UInt32(nameSources.count - 1)
        }
        nameStarts.append(UInt32(count))
        timing.mark("names")
        var directoryIDs: [FileIndexRawPath: Int] = [:], directories: [String] = []
        var parents = Array(repeating: UInt32(0), count: count), directoryCounts: [Int] = []
        var entryIDs = Array(repeating: UInt32(0), count: count)
        for (entry, sourceID) in paths.enumerated() {
            let source = Int(sourceID)
            if entry % 256 == 0 { try Task.checkCancellation() }
            let path = rawPaths[source]
            let parent = path.lastIndex(of: "/").map { String(path[..<$0]) } ?? ""
            let id: Int
            let key = FileIndexRawPath(value: parent)
            if let existing = directoryIDs[key] { id = existing }
            else { id = directories.count; directoryIDs[key] = id; directories.append(parent); directoryCounts.append(0) }
            parents[entry] = UInt32(id); directoryCounts[id] += 1; entryIDs[source] = UInt32(entry)
        }
        directoryIDs = [:]
        let directoryOrder = try directories.indices.sorted {
            try checkSortCancellation()
            return directories[$0] < directories[$1]
        }
        var remap = Array(repeating: 0, count: directories.count)
        for (new, old) in directoryOrder.enumerated() { remap[old] = new }
        directories = directoryOrder.map { directories[$0] }
        directoryCounts = directoryOrder.map { directoryCounts[$0] }
        for entry in parents.indices { parents[entry] = UInt32(remap[Int(parents[entry])]) }
        var directoryStarts = [0]
        for value in directoryCounts { directoryStarts.append(directoryStarts.last! + value) }
        var next = directoryStarts
        var directoryPostings = Array(repeating: UInt32(0), count: count)
        for entry in 0..<count {
            let parent = Int(parents[entry])
            directoryPostings[next[parent]] = UInt32(entry); next[parent] += 1
        }
        timing.mark("directories")
        let namesOffset = 64 + count * 40
        let dirsOffset = namesOffset + nameSources.count * 56
        let postingsOffset = dirsOffset + directories.count * 32
        let dirPostingsOffset = postingsOffset + count * 8
        let stringsOffset = dirPostingsOffset + count * 8
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else { throw FileSearchError.storage }
        var complete = false
        defer { if !complete { try? FileManager.default.removeItem(at: url) } }
        let records = try FileIndexSectionWriter(url: url, offset: 64)
        let nameRecords = try FileIndexSectionWriter(url: url, offset: namesOffset)
        let dirRecords = try FileIndexSectionWriter(url: url, offset: dirsOffset)
        let postings = try FileIndexSectionWriter(url: url, offset: postingsOffset)
        let dirPostings = try FileIndexSectionWriter(url: url, offset: dirPostingsOffset)
        let strings = try FileIndexSectionWriter(url: url, offset: stringsOffset)
        func string(_ value: String, into section: FileIndexSectionWriter) throws {
            try section.word(UInt64(strings.count)); try section.word(UInt64(value.utf8.count))
            try strings.bytes(value.utf8)
        }
        for (entry, sourceID) in paths.enumerated() {
            let source = Int(sourceID)
            if entry % 256 == 0 { try Task.checkCancellation() }
            let file = try fileAt(source)
            for value in [UInt64(nameIDs[source]), UInt64(bitPattern: file.size), file.modified.timeIntervalSinceReferenceDate.bitPattern,
                          file.isDirectory ? 1 : 0, UInt64(parents[entry])] { try records.word(value) }
        }
        rawPaths = []; paths = []; nameIDs = []; parents = []
        for (id, sourceID) in nameSources.enumerated() {
            let source = Int(sourceID)
            if id % 256 == 0 { try Task.checkCancellation() }
            let raw = rawNames[source]
            let start = strings.count
            try nameRecords.word(UInt64(start)); try nameRecords.word(UInt64(raw.length))
            try strings.bytes(arena.bytes(in: raw))
            if raw.offset == normalized[source].offset {
                try nameRecords.word(UInt64(start)); try nameRecords.word(UInt64(raw.length))
            } else {
                let folded = normalized[source]
                try nameRecords.word(UInt64(strings.count)); try nameRecords.word(UInt64(folded.length))
                try strings.bytes(arena.bytes(in: folded))
            }
            for value in [arena.mask(normalized[source]), UInt64(nameStarts[id]), UInt64(nameStarts[id + 1] - nameStarts[id])] {
                try nameRecords.word(value)
            }
        }
        // Release name storage before the remaining sections and mapped validation.
        let uniqueNameCount = nameSources.count
        normalized = []; rawNames = []; nameSources = []; nameStarts = []; arena = FileIndexBuildStrings()
        for (id, directory) in directories.enumerated() {
            try string(directory, into: dirRecords)
            try dirRecords.word(UInt64(directoryStarts[id])); try dirRecords.word(UInt64(directoryCounts[id]))
        }
        for i in 0..<count {
            if i % 256 == 0 { try Task.checkCancellation() }
            try postings.word(UInt64(entryIDs[Int(byName[i])])); try dirPostings.word(UInt64(directoryPostings[i]))
        }
        entryIDs = []; byName = []; directoryPostings = []
        let stringCount = strings.count
        try strings.bytes(metadata)
        for section in [records, nameRecords, dirRecords, postings, dirPostings, strings] { try section.close() }
        let header = try FileIndexSectionWriter(url: url, offset: 0)
        for value in [magic, 5, cursor, UInt64(count), UInt64(uniqueNameCount), UInt64(directories.count), UInt64(stringCount), UInt64(metadata.count)] {
            try header.word(value)
        }
        try header.close()
        complete = true
        timing.mark("encode_write")
    }
}

/// Swift String equality is canonical; directory storage must retain exact bytes.
private nonisolated struct FileIndexRawPath: Hashable {
    let value: String
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.value.utf8.elementsEqual(rhs.value.utf8) }
    func hash(into hasher: inout Hasher) {
        var string = value
        string.withUTF8 { hasher.combine(bytes: UnsafeRawBufferPointer($0)) }
    }
}

/// Swift orders strings by NFC scalar order. UTF-8 preserves that order, so
/// normalize comparison keys once rather than decoding names on every comparison.
/// The original bytes remain untouched for display and snapshot serialization.
private nonisolated struct FileIndexBuildStrings {
    struct Span {
        let offset: Int
        let length: UInt32
        var canonicalKey: UInt32 = .max
    }
    private var storage: [UInt8] = []
    private var canonicalKeys: [Span] = []
    mutating func append(_ string: String, canonical: String) -> Span {
        var span = Span(offset: storage.count, length: UInt32(string.utf8.count))
        storage.append(contentsOf: string.utf8)
        if !canonical.utf8.elementsEqual(string.utf8) {
            span.canonicalKey = UInt32(canonicalKeys.count)
            canonicalKeys.append(Span(offset: storage.count, length: UInt32(canonical.utf8.count)))
            storage.append(contentsOf: canonical.utf8)
        }
        return span
    }
    func bytes(in span: Span) -> ArraySlice<UInt8> { storage[span.offset..<(span.offset + Int(span.length))] }
    func compare(_ lhs: Span, _ rhs: Span) -> Int {
        let a = lhs.canonicalKey == .max ? lhs : canonicalKeys[Int(lhs.canonicalKey)]
        let b = rhs.canonicalKey == .max ? rhs : canonicalKeys[Int(rhs.canonicalKey)]
        if a.offset == b.offset { return 0 }
        let length = min(Int(a.length), Int(b.length))
        let order = length == 0 ? 0 : storage.withUnsafeBytes {
            Int(memcmp($0.baseAddress! + a.offset, $0.baseAddress! + b.offset, length))
        }
        return order == 0 ? Int(a.length) - Int(b.length) : order
    }
    func mask(_ span: Span) -> UInt64 {
        bytes(in: span).reduce(0) { $0 | (UInt64(1) << ($1 & 63)) }
    }
}

private nonisolated final class FileIndexSectionWriter {
    private let handle: FileHandle
    private var buffer: [UInt8] = []
    private(set) var count = 0
    init(url: URL, offset: Int) throws {
        buffer.reserveCapacity(65536)
        handle = try FileHandle(forWritingTo: url)
        try handle.seek(toOffset: UInt64(offset))
    }
    deinit { try? handle.close() }
    func word(_ value: UInt64) throws {
        var value = value.littleEndian
        try withUnsafeBytes(of: &value) { try bytes($0) }
    }
    func bytes<S: Collection>(_ bytes: S) throws where S.Element == UInt8 {
        buffer.append(contentsOf: bytes); count += bytes.count
        if buffer.count >= 65536 { try flush() }
    }
    private func flush() throws { try handle.write(contentsOf: Data(buffer)); buffer.removeAll(keepingCapacity: true) }
    func close() throws { try flush(); try handle.close() }
}

/// Directory conditions are resolved once. Only the remaining basename conditions need
/// a name lookup; a condition containing '/' may match across the parent/name boundary.
nonisolated struct FileIndexPathCandidates {
    private var entries: FileIndexBits
    let names: [Int]
    func contains(_ entry: Int) -> Bool { entries.contains(entry) }

    init(index: FileMappedIndex, terms: [String], root: FileSearchRoot) throws {
        enum Condition: Hashable { case contains(String), prefix(String) }
        var cached: [Condition: FileIndexBits] = [:]
        func names(for condition: Condition) throws -> FileIndexBits {
            if let result = cached[condition] { return result }
            var result = FileIndexBits(count: index.nameCount)
            switch condition {
            case .contains(let term):
                let mask = FileMappedIndex.mask(term)
                for id in 0..<index.nameCount {
                    if id % 256 == 0 { try Task.checkCancellation() }
                    if index.nameMask(id) & mask == mask, try index.normalizedName(id).contains(term) { result.insert(id) }
                }
            case .prefix(let term):
                if term.isEmpty {
                    for id in 0..<index.nameCount { result.insert(id) }
                } else {
                    for group in try index.nameGroups(phrase: term, sort: .relevance).prefix(2) {
                        for id in group.range { result.insert(id) }
                    }
                }
            }
            cached[condition] = result
            return result
        }
        var entries = FileIndexBits(count: index.count)
        var matchingNames = FileIndexBits(count: index.nameCount)
        for directoryID in 0..<index.directoryCount {
            try Task.checkCancellation()
            let relative = try index.directory(directoryID)
            var parent = IndexedFile.normalized(relative.isEmpty ? root.url.path : root.url.appending(path: relative).path)
            if !parent.hasSuffix("/") { parent += "/" }
            var conditions: [FileIndexBits] = []
            var possible = true
            for term in terms where !parent.contains(term) {
                let condition: Condition
                if let slash = term.lastIndex(of: "/") {
                    let end = term.index(after: slash)
                    guard parent.hasSuffix(term[..<end]) else { possible = false; break }
                    condition = .prefix(String(term[end...]))
                } else { condition = .contains(term) }
                let matches = try names(for: condition)
                guard !matches.isEmpty else { possible = false; break }
                conditions.append(matches)
            }
            guard possible else { continue }
            for posting in index.directoryEntries(directoryID) {
                if posting % 256 == 0 { try Task.checkCancellation() }
                let entry = index.directoryEntry(at: posting), name = index.nameID(entry)
                if conditions.allSatisfy({ $0.contains(name) }) {
                    entries.insert(entry); matchingNames.insert(name)
                }
            }
        }
        self.entries = entries
        self.names = matchingNames.indices
    }
}

private nonisolated struct FileIndexBits {
    var words: [UInt64]
    init(count: Int) { words = Array(repeating: 0, count: (count + 63) / 64) }
    mutating func insert(_ index: Int) { words[index / 64] |= UInt64(1) << (index % 64) }
    func contains(_ index: Int) -> Bool { words[index / 64] & (UInt64(1) << (index % 64)) != 0 }
    var isEmpty: Bool { words.allSatisfy { $0 == 0 } }
    var indices: [Int] {
        var result: [Int] = []
        for (i, value) in words.enumerated() {
            var bits = value
            while bits != 0 {
                result.append(i * 64 + bits.trailingZeroBitCount)
                bits &= bits - 1
            }
        }
        return result
    }
}

/// Compiled output is limited to the synthetic benchmark; no user paths or names are logged.
private nonisolated struct FileIndexBuildTiming {
#if FILE_INDEX_BENCHMARK
    private var last = ContinuousClock.now
#endif
    mutating func mark(_ phase: StaticString) {
#if FILE_INDEX_BENCHMARK
        let now = ContinuousClock.now
        let elapsed = last.duration(to: now)
        print("build_phase=\(phase) ms=\(Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15)")
        last = now
#endif
    }
}
