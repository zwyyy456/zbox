import Foundation

nonisolated enum ApplicationSearchAliases {
    static func make(for applicationName: String) -> [CommandSearchAlias] {
        guard let transliterated = applicationName.applyingTransform(.toLatin, reverse: false) else {
            return []
        }

        let words = transliterated
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return [] }

        let full = words.joined(separator: " ")
        let normalizedName = applicationName
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased()
        guard full != normalizedName else { return [] }

        var aliases = [CommandSearchAlias(value: full, kind: .transliteration)]
        let compact = words.joined()
        if compact != full {
            aliases.append(CommandSearchAlias(value: compact, kind: .transliteration))
        }

        let initials = String(words.compactMap(\.first))
        if initials.count > 1, initials != compact {
            aliases.append(CommandSearchAlias(value: initials, kind: .initials))
        }
        return aliases
    }
}
