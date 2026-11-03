import Foundation

struct ApplicationInfo: Identifiable, Sendable {
    let id: String
    let name: String
    let bundleIdentifier: String?
    let url: URL
}

struct ApplicationCatalog {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func loadApplications() -> [ApplicationInfo] {
        let roots = [
            URL(filePath: "/Applications", directoryHint: .isDirectory),
            URL(filePath: "/System/Applications", directoryHint: .isDirectory),
            fileManager.homeDirectoryForCurrentUser
                .appending(path: "Applications", directoryHint: .isDirectory),
        ]

        var applicationsByID: [String: ApplicationInfo] = [:]

        for root in roots where fileManager.fileExists(atPath: root.path) {
            for application in applications(in: root) {
                applicationsByID[application.id] = application
            }
        }

        return applicationsByID.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private func applications(in root: URL) -> [ApplicationInfo] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var applications: [ApplicationInfo] = []

        for case let url as URL in enumerator where url.pathExtension.caseInsensitiveCompare("app") == .orderedSame {
            enumerator.skipDescendants()
            applications.append(makeApplicationInfo(url: url))
        }

        return applications
    }

    private func makeApplicationInfo(url: URL) -> ApplicationInfo {
        let bundle = Bundle(url: url)
        let bundleIdentifier = bundle?.bundleIdentifier
        let displayName = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        let identity = bundleIdentifier?.lowercased() ?? url.standardizedFileURL.path

        return ApplicationInfo(
            id: identity,
            name: displayName,
            bundleIdentifier: bundleIdentifier,
            url: url.standardizedFileURL
        )
    }
}
