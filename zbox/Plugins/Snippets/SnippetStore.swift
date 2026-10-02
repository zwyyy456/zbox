import Foundation
import Observation

nonisolated struct Snippet: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name = ""
    var keywords = ""
    var group = ""
    var body = ""
    var commandID: CommandID { CommandID("snippets.\(id.uuidString)") }
}

nonisolated enum SnippetError: LocalizedError {
    case unreadableData, invalidContent, copyFailed
    var errorDescription: String? {
        switch self {
        case .unreadableData: String(localized: "Snippets could not be read. The saved file has been preserved.")
        case .invalidContent: String(localized: "Enter a name and snippet text.")
        case .copyFailed: String(localized: "The snippet could not be copied. Try again.")
        }
    }
}

@MainActor @Observable
final class SnippetStore {
    private let fileURL: URL
    private(set) var items: [Snippet] = []
    private(set) var loadError: String?

    init(fileURL: URL = URL.applicationSupportDirectory.appending(path: "zbox/snippets.json")) {
        self.fileURL = fileURL
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do { items = try JSONDecoder().decode([Snippet].self, from: Data(contentsOf: fileURL)) }
        catch { loadError = SnippetError.unreadableData.localizedDescription }
    }

    func save(_ item: Snippet) throws {
        guard !item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !item.body.isEmpty else {
            throw SnippetError.invalidContent
        }
        var updated = items
        if let index = updated.firstIndex(where: { $0.id == item.id }) { updated[index] = item }
        else { updated.append(item) }
        try persist(updated)
    }

    func delete(_ id: UUID) throws { try persist(items.filter { $0.id != id }) }

    private func persist(_ updated: [Snippet]) throws {
        guard loadError == nil else { throw SnippetError.unreadableData }
        let data = try JSONEncoder().encode(updated)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        items = updated
    }
}
