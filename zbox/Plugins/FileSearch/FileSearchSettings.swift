import Foundation
import Observation

nonisolated struct FileSearchRoot: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    let url: URL
    let volumeID: String
    let fileID: UInt64
    var includesHidden = false
    var exclusions: [String] = []

    static var privateDataDirectory: URL { URL.applicationSupportDirectory.appending(path: "zbox").standardizedFileURL }

    static func contains(_ child: URL, in parent: URL) -> Bool {
        child.path == parent.path || child.path.hasPrefix(parent.path == "/" ? "/" : parent.path + "/")
    }

    static func selected(_ url: URL) throws -> Self {
        let url = url.resolvingSymlinksInPath().standardizedFileURL
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .volumeIsLocalKey, .volumeUUIDStringKey])
        guard values.isDirectory == true, values.volumeIsLocal == true,
              let volumeID = values.volumeUUIDString,
              let number = try FileManager.default.attributesOfItem(atPath: url.path)[.systemFileNumber] as? NSNumber else {
            throw FileSearchError.unsupportedRoot
        }
        return Self(url: url, volumeID: volumeID, fileID: number.uint64Value)
    }

    func isAvailable() -> Bool {
        guard FileManager.default.isReadableFile(atPath: url.path),
              let current = try? Self.selected(url) else { return false }
        return current.volumeID == volumeID && current.fileID == fileID
    }
}

nonisolated enum FileSearchError: LocalizedError {
    case unsupportedRoot, overlappingRoot, outsideRoot, settingsUnreadable, storage, unavailable, scanIncomplete, invalidQuery, missingFile, actionFailed, watcherFailed
    var errorDescription: String? {
        switch self {
        case .watcherFailed: String(localized: "File changes could not be monitored. Check access and rescan.")
        case .unsupportedRoot: String(localized: "Choose a folder on a local disk.")
        case .overlappingRoot: String(localized: "This folder overlaps an existing search folder.")
        case .outsideRoot: String(localized: "Choose a subfolder inside this search folder.")
        case .settingsUnreadable: String(localized: "File Search settings could not be read. Saved data has been preserved.")
        case .storage: String(localized: "The file index could not be opened or saved.")
        case .unavailable: String(localized: "The search folder is unavailable or its disk identity has changed.")
        case .scanIncomplete: String(localized: "Some folders could not be scanned. The index is incomplete; check access and rescan.")
        case .invalidQuery: String(localized: "Check the quotes and filters. Supported filters: ext:, type:file, type:folder, path:.")
        case .missingFile: String(localized: "This item is no longer accessible. Its search folder will be refreshed.")
        case .actionFailed: String(localized: "The file operation could not be completed.")
        }
    }
}

@MainActor @Observable
final class FileSearchSettings {
    private let fileURL: URL
    private(set) var roots: [FileSearchRoot] = []
    private(set) var error: String?

    init(fileURL: URL = URL.applicationSupportDirectory.appending(path: "zbox/file-search-folders.json")) {
        self.fileURL = fileURL
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do { roots = try JSONDecoder().decode([FileSearchRoot].self, from: Data(contentsOf: fileURL)) }
        catch { self.error = FileSearchError.settingsUnreadable.localizedDescription }
    }

    func save(_ root: FileSearchRoot) throws {
        guard !roots.contains(where: { $0.id != root.id &&
            (FileSearchRoot.contains(root.url, in: $0.url) || FileSearchRoot.contains($0.url, in: root.url)) }) else {
            throw FileSearchError.overlappingRoot
        }
        var updated = roots
        if let index = updated.firstIndex(where: { $0.id == root.id }) { updated[index] = root }
        else { updated.append(root) }
        try persist(updated)
    }

    func remove(_ id: UUID) throws { try persist(roots.filter { $0.id != id }) }

    private func persist(_ roots: [FileSearchRoot]) throws {
        guard error == nil else { throw FileSearchError.settingsUnreadable }
        let data = try JSONEncoder().encode(roots)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        self.roots = roots
    }
}
