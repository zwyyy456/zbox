import Foundation
import Darwin

actor FileIndexScanner {
    func availableRoots(_ roots: [FileSearchRoot]) -> [FileSearchRoot] { roots.filter { $0.isAvailable() } }
    func reconcile(_ root: FileSearchRoot, change: FileIndexChange, store: FileIndexStore) async throws {
        for directory in change.minimalDirectories {
            _ = try await scan(root, directory: directory, store: store)
        }
        for directory in change.minimalShallowDirectories {
            _ = try await scan(root, directory: directory, recursive: false, store: store)
        }
        try Task.checkCancellation()
        let previous = try await store.cursor(root: root.id) ?? 0
        try await store.setCursor(max(previous, change.eventID), root: root.id)
    }

    func scan(_ root: FileSearchRoot, directory: String = "", recursive: Bool = true, store: FileIndexStore) async throws -> Int {
        try Task.checkCancellation()
        guard root.isAvailable() else { throw FileSearchError.unavailable }
        // Events can originate inside packages or symlinked directories that enumeration would skip.
        var ancestor = root.url
        for component in directory.split(separator: "/").dropLast() {
            ancestor.append(path: String(component))
            let values = try ancestor.resourceValues(forKeys: [.isPackageKey, .isSymbolicLinkKey, .isHiddenKey])
            if values.isPackage == true || values.isSymbolicLink == true || (!root.includesHidden && values.isHidden == true) { return 0 }
        }
        let start = directory.isEmpty ? root.url : root.url.appending(path: directory)
        let generation = UUID()
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey, .isHiddenKey,
                                        .fileSizeKey, .contentModificationDateKey]
        var incomplete = false
        var batch: [IndexedFile] = []
        var count = 0
        func record(_ url: URL) throws -> URLResourceValues {
            let values = try url.resourceValues(forKeys: keys)
            let relative = String(url.standardizedFileURL.path.dropFirst(root.url.path == "/" ? 1 : root.url.path.count + 1))
            batch.append(IndexedFile(rootID: root.id, path: relative, name: url.lastPathComponent,
                isDirectory: values.isDirectory == true, size: Int64(values.fileSize ?? 0),
                modified: values.contentModificationDate ?? .distantPast))
            count += 1
            return values
        }
        if !directory.isEmpty {
            // A removed subtree can be pruned only when its parent is still accessible.
            do {
                let values = try record(start)
                if !root.includesHidden && values.isHidden == true {
                    try await store.finishScan(root: root.id, directory: directory, generation: generation)
                    return 0
                }
                if values.isSymbolicLink == true || values.isPackage == true || values.isDirectory != true {
                    try await store.upsert(batch, generation: generation)
                    try await store.finishScan(root: root.id, directory: directory, generation: generation)
                    return count
                }
            }
            catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
                _ = try FileManager.default.contentsOfDirectory(atPath: start.deletingLastPathComponent().path)
                try await store.finishScan(root: root.id, directory: directory, generation: generation)
                return 0
            }
        }
        var directories = [start]
        while let directoryURL = directories.popLast() {
            try Task.checkCancellation()
            do {
                let reader = try FileBulkDirectoryReader(url: directoryURL)
                while let entries = try reader.next() {
                    for entry in entries {
                        try Task.checkCancellation()
                        let url = directoryURL.appending(path: entry.name)
                        if FileSearchRoot.contains(url, in: FileSearchRoot.privateDataDirectory) { continue }
                        let relative = String(url.path.dropFirst(root.url.path == "/" ? 1 : root.url.path.count + 1))
                        if root.exclusions.contains(where: { relative == $0 || relative.hasPrefix($0 + "/") }) { continue }
                        if !root.includesHidden && entry.hidden { continue }
                        if entry.type == UInt32(VREG.rawValue) {
                            batch.append(IndexedFile(rootID: root.id, path: relative, name: entry.name,
                                isDirectory: false, size: entry.size, modified: entry.modified))
                            count += 1
                        } else {
                            // Foundation remains responsible for package semantics and the
                            // metadata of links, mounted directories and special objects.
                            do {
                                let values = try url.resourceValues(forKeys: keys)
                                if !root.includesHidden && values.isHidden == true { continue }
                                _ = try record(url)
                                if recursive, values.isDirectory == true, values.isSymbolicLink != true, values.isPackage != true {
                                    directories.append(url)
                                }
                            } catch { incomplete = true }
                        }
                        if batch.count >= 256 {
                            try await store.upsert(batch, generation: generation)
                            batch.removeAll(keepingCapacity: true)
                            await Task.yield()
                        }
                    }
                }
            } catch is CancellationError { throw CancellationError() }
            catch { incomplete = true }
        }
        try await store.upsert(batch, generation: generation)
        try Task.checkCancellation()
        guard !incomplete else { throw FileSearchError.scanIncomplete }
        try await store.finishScan(root: root.id, directory: directory, generation: generation, recursive: recursive)
        return count
    }
}

/// Darwin's packed attribute buffer is an OS boundary; validate each returned
/// field before decoding. No filesystem error is interpreted as an empty directory.
private nonisolated final class FileBulkDirectoryReader {
    struct Entry {
        let name: String
        let type: UInt32
        let size: Int64
        let modified: Date
        let hidden: Bool
    }
    private let descriptor: Int32
    private var buffer = [UInt8](repeating: 0, count: 64 * 1024)
    private var attributes = attrlist()
    init(url: URL) throws {
        descriptor = open(url.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { throw FileSearchError.scanIncomplete }
        attributes.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
        attributes.commonattr = ATTR_CMN_RETURNED_ATTRS | UInt32(ATTR_CMN_ERROR | ATTR_CMN_NAME |
            ATTR_CMN_OBJTYPE | ATTR_CMN_MODTIME | ATTR_CMN_FNDRINFO | ATTR_CMN_FLAGS)
        attributes.fileattr = UInt32(ATTR_FILE_DATALENGTH)
    }
    deinit { close(descriptor) }
    func next() throws -> [Entry]? {
        try Task.checkCancellation()
        let count = buffer.withUnsafeMutableBytes {
            getattrlistbulk(descriptor, &attributes, $0.baseAddress!, $0.count, UInt64(FSOPT_PACK_INVAL_ATTRS))
        }
        guard count >= 0 else { throw FileSearchError.scanIncomplete }
        guard count > 0 else { return nil }
        return try buffer.withUnsafeBytes { bytes in
            var result: [Entry] = []
            result.reserveCapacity(Int(count))
            var record = 0
            for _ in 0..<count {
                try Task.checkCancellation()
                guard record + 4 <= bytes.count else { throw FileSearchError.scanIncomplete }
                let length = Int(bytes.loadUnaligned(fromByteOffset: record, as: UInt32.self))
                guard length >= 92, length <= bytes.count - record else { throw FileSearchError.scanIncomplete }
                // 4 length, 20 returned attrs, 4 error, 8 name ref, 4 type,
                // 16 modification time, 32 FinderInfo, 4 flags. File data length
                // follows only for file objects; PACK_INVAL_ATTRS does not add it to directories.
                let returned = bytes.loadUnaligned(fromByteOffset: record + 4, as: attribute_set_t.self)
                let error = bytes.loadUnaligned(fromByteOffset: record + 24, as: UInt32.self)
                let required = UInt32(ATTR_CMN_NAME | ATTR_CMN_OBJTYPE | ATTR_CMN_MODTIME | ATTR_CMN_FLAGS)
                guard error == 0, returned.commonattr & required == required else { throw FileSearchError.scanIncomplete }
                let ref = bytes.loadUnaligned(fromByteOffset: record + 28, as: attrreference_t.self)
                let nameStart = record + 28 + Int(ref.attr_dataoffset), nameLength = Int(ref.attr_length)
                guard nameLength > 0, nameStart >= record + 92 + (returned.fileattr & UInt32(ATTR_FILE_DATALENGTH) != 0 ? 8 : 0),
                      nameStart <= record + length, nameLength <= record + length - nameStart,
                      bytes[nameStart + nameLength - 1] == 0,
                      let name = String(bytes: bytes[nameStart..<(nameStart + nameLength - 1)], encoding: .utf8),
                      !name.isEmpty, !name.contains("/"), name != ".", name != ".." else { throw FileSearchError.scanIncomplete }
                let type = bytes.loadUnaligned(fromByteOffset: record + 36, as: UInt32.self)
                let time = bytes.loadUnaligned(fromByteOffset: record + 40, as: timespec.self)
                let flags = bytes.loadUnaligned(fromByteOffset: record + 88, as: UInt32.self)
                let size = returned.fileattr & UInt32(ATTR_FILE_DATALENGTH) != 0
                    ? bytes.loadUnaligned(fromByteOffset: record + 92, as: Int64.self) : 0
                if type == UInt32(VREG.rawValue), returned.fileattr & UInt32(ATTR_FILE_DATALENGTH) == 0 { throw FileSearchError.scanIncomplete }
                let finderHidden = returned.commonattr & UInt32(ATTR_CMN_FNDRINFO) != 0 && bytes[record + 64] & 0x40 != 0
                result.append(Entry(name: name, type: type, size: size,
                    modified: Date(timeIntervalSinceReferenceDate: Double(time.tv_sec) - Date.timeIntervalBetween1970AndReferenceDate + Double(time.tv_nsec) / 1e9),
                    hidden: name.hasPrefix(".") || flags & UInt32(UF_HIDDEN) != 0 || finderHidden))
                record += length
            }
            return result
        }
    }
}
