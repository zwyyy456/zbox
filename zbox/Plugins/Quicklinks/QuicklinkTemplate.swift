import Foundation

nonisolated struct QuicklinkTemplate {
    let source: String

    init(_ source: String) throws {
        guard source.contains("{query}") else { throw QuicklinkError.invalidTemplate }
        let remainder = source.replacingOccurrences(of: "{query}", with: "")
        guard !remainder.contains("{"), !remainder.contains("}") else { throw QuicklinkError.invalidTemplate }
        var marker = "ZBOXQUERY"
        while source.contains(marker) { marker += "X" }
        let probe = source.replacingOccurrences(of: "{query}", with: marker)
        guard let parts = URLComponents(string: probe),
              ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
              let host = parts.host, !host.isEmpty,
              ![parts.host, parts.user, parts.password, parts.fragment].compactMap({ $0 }).contains(where: { $0.contains(marker) }),
              !(parts.queryItems ?? []).contains(where: { $0.name.contains(marker) }),
              parts.url != nil else { throw QuicklinkError.invalidTemplate }
        // A placeholder may occupy a path segment or a query value, never URL structure.
        let allowed = [parts.path] + (parts.queryItems ?? []).compactMap(\.value)
        let count = allowed.reduce(0) { $0 + $1.components(separatedBy: marker).count - 1 }
        guard count == source.components(separatedBy: "{query}").count - 1 else { throw QuicklinkError.invalidTemplate }
        self.source = source
    }

    func destination(query: String) throws -> URL {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let encoded = query.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")),
              let url = URL(string: source.replacingOccurrences(of: "{query}", with: encoded)) else {
            throw QuicklinkError.emptyQuery
        }
        return url
    }
}
