import Foundation

actor FileIndexScanner {
    func scan(_ root: FileSearchRoot, directory: String = "", store: FileIndexStore) async throws -> Int {
        try Task.checkCancellation()
        guard root.isAvailable() else { throw FileSearchError.unavailable }
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
            do { _ = try record(start) }
            catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
                _ = try FileManager.default.contentsOfDirectory(atPath: start.deletingLastPathComponent().path)
                try await store.finishScan(root: root.id, directory: directory, generation: generation)
                return 0
            }
        }
        // Prove directory access explicitly: a nil/empty enumerator must not imply a complete scan.
        _ = try FileManager.default.contentsOfDirectory(atPath: start.path)
        var options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        if !root.includesHidden { options.insert(.skipsHiddenFiles) }
        guard let enumerator = FileManager.default.enumerator(at: start, includingPropertiesForKeys: Array(keys), options: options,
            errorHandler: { _, _ in incomplete = true; return true }) else { throw FileSearchError.scanIncomplete }
        while let url = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            let relative = String(url.standardizedFileURL.path.dropFirst(root.url.path == "/" ? 1 : root.url.path.count + 1))
            if root.exclusions.contains(where: { relative == $0 || relative.hasPrefix($0 + "/") }) {
                enumerator.skipDescendants()
                continue
            }
            do {
                let values = try record(url)
                if values.isSymbolicLink == true || values.isPackage == true { enumerator.skipDescendants() }
            } catch { incomplete = true; enumerator.skipDescendants() }
            if batch.count >= 256 {
                try await store.upsert(batch, generation: generation)
                batch.removeAll(keepingCapacity: true)
                await Task.yield()
            }
        }
        try await store.upsert(batch, generation: generation)
        try Task.checkCancellation()
        guard !incomplete else { throw FileSearchError.scanIncomplete }
        try await store.finishScan(root: root.id, directory: directory, generation: generation)
        return count
    }
}
