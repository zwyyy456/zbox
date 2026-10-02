import Foundation

nonisolated enum FileSearchSort: String, CaseIterable, Sendable { case relevance, name, modified }

nonisolated struct FileSearchQuery: Sendable {
    var names: [String] = []
    var paths: [String] = []
    var extensions: [String] = []
    var types: [String] = []
    var isEmpty: Bool { names.isEmpty && paths.isEmpty && extensions.isEmpty && types.isEmpty }

    init(_ input: String, extensionFilter: String = "", typeFilter: String = "") throws {
        var tokens: [String] = []
        var token = ""
        var quoted = false
        for character in input {
            if character == "\"" { quoted.toggle() }
            else if character.isWhitespace && !quoted {
                if !token.isEmpty { tokens.append(token); token = "" }
            } else { token.append(character) }
        }
        guard !quoted else { throw FileSearchError.invalidQuery }
        if !token.isEmpty { tokens.append(token) }
        for token in tokens {
            let value = IndexedFile.normalized(token)
            if value.hasPrefix("ext:") {
                let ext = String(value.dropFirst(4)).trimmingCharacters(in: CharacterSet(charactersIn: "."))
                guard !ext.isEmpty else { throw FileSearchError.invalidQuery }
                extensions.append(ext)
            } else if value.hasPrefix("type:") {
                let type = String(value.dropFirst(5))
                guard ["file", "folder"].contains(type) else { throw FileSearchError.invalidQuery }
                types.append(type)
            } else if value.hasPrefix("path:") {
                let path = String(value.dropFirst(5))
                guard !path.isEmpty else { throw FileSearchError.invalidQuery }
                paths.append(path)
            } else { names.append(value) }
        }
        if !extensionFilter.isEmpty { extensions.append(IndexedFile.normalized(extensionFilter.trimmingCharacters(in: CharacterSet(charactersIn: ". ")))) }
        if !typeFilter.isEmpty { types.append(typeFilter) }
    }

    func score(_ file: IndexedFile, root: FileSearchRoot) -> Int? {
        guard !root.exclusions.contains(where: { file.path == $0 || file.path.hasPrefix($0 + "/") }),
              root.includesHidden || !file.path.split(separator: "/").contains(where: { $0.hasPrefix(".") }),
              types.allSatisfy({ $0 == (file.isDirectory ? "folder" : "file") }),
              extensions.allSatisfy({ !file.isDirectory && file.fileExtension == $0 }) else { return nil }
        let name = IndexedFile.normalized(file.name)
        guard names.allSatisfy({ name.contains($0) }) else { return nil }
        let path = IndexedFile.normalized(root.url.appending(path: file.path).path)
        guard paths.allSatisfy({ path.contains($0) }) else { return nil }
        let phrase = names.joined(separator: " ")
        if !phrase.isEmpty && name == phrase { return 3 }
        if !phrase.isEmpty && name.hasPrefix(phrase) { return 2 }
        return 1
    }
}

nonisolated struct FileSearchPage: Sendable {
    var files: [IndexedFile] = []
    var hasMore = false
}
