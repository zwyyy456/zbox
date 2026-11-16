import Foundation
import SystemDictionaryBridge

public struct SystemDictionaryEntry: Identifiable, Sendable {
    public let id: String
    public let dictionaryName: String
    public let headword: String
    public let html: String
    public let contentsURL: URL
    public init(id: String, dictionaryName: String, headword: String, html: String, contentsURL: URL) {
        self.id = id; self.dictionaryName = dictionaryName; self.headword = headword
        self.html = html; self.contentsURL = contentsURL
    }
}

public enum SystemDictionaryError: Error { case noActiveDictionaries, noResult }

/// Owns all synchronous private DictionaryServices calls and their cached CF objects.
public actor SystemDictionaryReader {
    public static let shared = SystemDictionaryReader()
    private init() {}
    public func lookup(_ term: String) throws -> [SystemDictionaryEntry] {
        try Task.checkCancellation()
        guard ZDSystemDictionaryCount() > 0 else { throw SystemDictionaryError.noActiveDictionaries }
        let entries = ZDSystemDictionaryEntries(term).enumerated().compactMap { index, item -> SystemDictionaryEntry? in
            guard let identifier = item["identifier"] as? String, let name = item["name"] as? String,
                  let html = item["html"] as? String, let url = item["url"] as? URL,
                  let headword = item["headword"] as? String,
                  SystemDictionaryHeadword.matches(headword, query: term) else { return nil }
            return SystemDictionaryEntry(id: "\(identifier)-\(index)", dictionaryName: name,
                headword: headword, html: html, contentsURL: url.appendingPathComponent("Contents"))
        }
        try Task.checkCancellation()
        guard !entries.isEmpty else { throw SystemDictionaryError.noResult }
        return entries
    }
}

/// Resolves resources from the owning dictionary bundle; never grants general file access to WebKit.
public enum SystemDictionaryResource {
    public static func resolve(_ path: String, contentsURL: URL, relativeTo base: URL? = nil) -> URL? {
        let root = contentsURL.standardizedFileURL.resolvingSymlinksInPath()
        let decoded = path.removingPercentEncoding ?? path
        let candidates: [URL]
        if decoded.hasPrefix("/") { candidates = [URL(fileURLWithPath: decoded)] }
        else if let base { candidates = [base.appendingPathComponent(decoded)] }
        else { candidates = [root.appendingPathComponent("Resources").appendingPathComponent(decoded), root.appendingPathComponent(decoded)] }
        return candidates.map { $0.standardizedFileURL.resolvingSymlinksInPath() }.first {
            $0.path.hasPrefix(root.path + "/") && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
    }
}

/// DictionaryServices exact search also returns Chinese phonetic matches for Latin words.
enum SystemDictionaryHeadword {
    static func matches(_ headword: String, query: String) -> Bool {
        func normalized(_ value: String) -> String {
            value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        }
        let word = normalized(query), title = normalized(headword)
        guard !word.isEmpty else { return false }
        let latin = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz")
        let firstQueryLetter = word.unicodeScalars.first { CharacterSet.letters.contains($0) }
        let firstHeadwordLetter = title.unicodeScalars.first { CharacterSet.letters.contains($0) }
        if let firstQueryLetter, latin.contains(firstQueryLetter) {
            guard let firstHeadwordLetter, latin.contains(firstHeadwordLetter) else { return false }
            // Keep the framework's inflection matches, e.g. running → run and children → child.
            return title.replacingOccurrences(of: word, with: "") != "-"
        }
        return title.contains(word) && title.replacingOccurrences(of: word, with: "") != "-"
    }
}
