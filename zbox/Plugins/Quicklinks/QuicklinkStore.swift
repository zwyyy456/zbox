import Foundation
import Observation

nonisolated struct Quicklink: Codable, Identifiable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable { case url, file, template }
    var id = UUID()
    var name = ""
    var kind = Kind.url
    var target = ""
    var keywords = ""
    var parameterPrompt: String?
    var commandID: CommandID { CommandID("quicklinks.\(id.uuidString)") }

    func destination() throws -> URL {
        if kind == .template { return try QuicklinkTemplate(target).destination(query: "example") }
        if kind == .file {
            guard target.hasPrefix("/") else { throw QuicklinkError.invalidTarget }
            return URL(fileURLWithPath: target)
        }
        guard let url = URL(string: target), let scheme = url.scheme?.lowercased(),
              !["javascript", "data", "file"].contains(scheme),
              !target.contains("{"), !target.contains("}"),
              !["http", "https"].contains(scheme) || url.host?.isEmpty == false else {
            throw QuicklinkError.invalidTarget
        }
        return url
    }
}

nonisolated enum QuicklinkError: LocalizedError {
    case invalidTarget, missingFile, openFailed, unreadableData, invalidTemplate, emptyQuery
    var errorDescription: String? {
        switch self {
        case .invalidTemplate: String(localized: "Use {query} in an HTTP(S) URL path or query value, not in its host, parameter name, or fragment.")
        case .emptyQuery: String(localized: "Enter a search value.")
        case .invalidTarget: String(localized: "Enter a valid URL or choose a file or folder.")
        case .missingFile: String(localized: "This file or folder no longer exists. Choose its new location in Settings.")
        case .openFailed: String(localized: "The system could not open this quicklink. Check its address and installed app.")
        case .unreadableData: String(localized: "Quicklinks could not be read. The saved file has been preserved.")
        }
    }
}

@MainActor @Observable
final class QuicklinkStore {
    private let fileURL: URL
    private(set) var items: [Quicklink] = []
    private(set) var loadError: String?

    init(fileURL: URL = URL.applicationSupportDirectory.appending(path: "zbox/quicklinks.json")) {
        self.fileURL = fileURL
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do { items = try JSONDecoder().decode([Quicklink].self, from: Data(contentsOf: fileURL)) }
        catch { loadError = QuicklinkError.unreadableData.localizedDescription }
    }

    func save(_ item: Quicklink) throws {
        _ = try item.destination()
        var updated = items
        if let index = updated.firstIndex(where: { $0.id == item.id }) { updated[index] = item }
        else { updated.append(item) }
        try persist(updated)
    }

    func delete(_ id: UUID) throws { try persist(items.filter { $0.id != id }) }

    private func persist(_ updated: [Quicklink]) throws {
        guard loadError == nil else { throw QuicklinkError.unreadableData }
        let data = try JSONEncoder().encode(updated)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        items = updated
    }
}
