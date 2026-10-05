import Foundation

nonisolated struct ExtensionInstallation: Codable, Identifiable, Sendable {
    var manifest: ExtensionManifest
    let directory: String
    let source: String
    var enabled: Bool
    var grants: [String]
    var settings: [String: String]
    var id: String { manifest.id }
}

actor ExtensionPackageStore {
    nonisolated let root: URL
    init(root: URL = URL.applicationSupportDirectory.appending(path: "zbox/extensions")) { self.root = root }

    nonisolated func packageURL(_ item: ExtensionInstallation) -> URL { root.appending(path: "packages/\(item.directory)") }
    nonisolated func dataURL(_ id: String) -> URL { root.appending(path: "data/\(id)") }

    func load() throws -> [ExtensionInstallation] {
        let index = root.appending(path: "installed.json")
        guard FileManager.default.fileExists(atPath: index.path) else { return [] }
        let items = try JSONDecoder().decode([ExtensionInstallation].self, from: Data(contentsOf: index))
        guard Set(items.map(\.id)).count == items.count else { throw ExtensionFailure("Duplicate installed extension IDs.") }
        for item in items {
            try item.manifest.validate()
            guard UUID(uuidString: item.directory) != nil else { throw ExtensionFailure("Invalid installed package directory.") }
        }
        return items
    }

    func prepare(_ source: URL) throws -> ExtensionInstallation {
        let folder = UUID().uuidString
        let destination = root.appending(path: "packages/\(folder)")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        do {
            let info = try source.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey])
            guard info.isSymbolicLink != true else { throw ExtensionFailure("Choose an ordinary package, not a symbolic link.") }
            if info.isDirectory == true { try ExtensionArchive.copyDirectory(source.resolvingSymlinksInPath(), to: destination) }
            else if info.isRegularFile == true { try ExtensionArchive.extract(source, to: destination) }
            else { throw ExtensionFailure("Choose a package directory or ZIP file.") }
            let manifestURL = destination.appending(path: "manifest.json")
            let size = try manifestURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 1_048_576 else { throw ExtensionFailure("The manifest exceeds 1 MiB.") }
            let manifest = try JSONDecoder().decode(ExtensionManifest.self, from: Data(contentsOf: manifestURL))
            try manifest.validate()
            try manifest.checkEnvironment()
            for command in manifest.commands {
                let entry = destination.appending(path: command.entry)
                guard try entry.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { throw ExtensionFailure("The entry must be a regular file.") }
                // Check executables without running package code or requiring user parameters.
                _ = try command.invocation(root: destination, values: (command.parameters ?? []).map { $0.defaultValue ?? "validation" })
            }
            return ExtensionInstallation(manifest: manifest, directory: folder, source: source.path, enabled: true,
                                         grants: manifest.capabilities ?? [], settings: [:])
        } catch {
            try FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    func save(_ items: [ExtensionInstallation]) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(items).write(to: root.appending(path: "installed.json"), options: .atomic)
    }

    func discard(_ item: ExtensionInstallation) throws { try FileManager.default.removeItem(at: packageURL(item)) }
    func removeData(_ id: String) throws {
        let directory = dataURL(id)
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }
}
