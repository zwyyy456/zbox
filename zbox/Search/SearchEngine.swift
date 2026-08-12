import Foundation

nonisolated struct SearchMatch: Identifiable, Sendable {
    let descriptor: CommandDescriptor
    let score: Int

    var id: CommandID { descriptor.id }
}

nonisolated struct SearchEngine {
    func search(
        query: String,
        in commands: [CommandDescriptor],
        limit: Int
    ) -> [SearchMatch] {
        guard limit > 0 else { return [] }

        let normalizedQuery = normalize(query)
        guard !normalizedQuery.isEmpty else {
            return commands.prefix(limit).map {
                SearchMatch(descriptor: $0, score: 0)
            }
        }

        return commands
            .compactMap { descriptor -> SearchMatch? in
                guard let score = score(descriptor, for: normalizedQuery) else {
                    return nil
                }
                return SearchMatch(descriptor: descriptor, score: score)
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }

                let lhsTitle = normalize(lhs.descriptor.title)
                let rhsTitle = normalize(rhs.descriptor.title)
                if lhsTitle != rhsTitle {
                    return lhsTitle < rhsTitle
                }
                return lhs.id.rawValue < rhs.id.rawValue
            }
            .prefix(limit)
            .map(\.self)
    }

    private func score(_ descriptor: CommandDescriptor, for query: String) -> Int? {
        let title = normalize(descriptor.title)

        if title == query { return 1_000 }
        if title.hasPrefix(query) { return 900 }
        if title.contains(query) { return 700 }

        var bestKeywordScore: Int?
        for keyword in descriptor.keywords.map(normalize) {
            let keywordScore: Int?
            if keyword == query {
                keywordScore = 650
            } else if keyword.hasPrefix(query) {
                keywordScore = 600
            } else if keyword.contains(query) {
                keywordScore = 550
            } else {
                keywordScore = fuzzyScore(query: query, candidate: keyword).map { 350 + $0 }
            }

            if let keywordScore {
                bestKeywordScore = max(bestKeywordScore ?? keywordScore, keywordScore)
            }
        }

        let titleFuzzyScore = fuzzyScore(query: query, candidate: title).map { 400 + $0 }
        return [bestKeywordScore, titleFuzzyScore].compactMap(\.self).max()
    }

    private func fuzzyScore(query: String, candidate: String) -> Int? {
        let queryCharacters = Array(query)
        let candidateCharacters = Array(candidate)
        guard !queryCharacters.isEmpty else { return 0 }

        var queryIndex = 0
        var firstMatchIndex: Int?
        var lastMatchIndex = 0

        for (candidateIndex, character) in candidateCharacters.enumerated() {
            guard character == queryCharacters[queryIndex] else { continue }

            firstMatchIndex = firstMatchIndex ?? candidateIndex
            lastMatchIndex = candidateIndex
            queryIndex += 1
            if queryIndex == queryCharacters.count {
                let span = lastMatchIndex - (firstMatchIndex ?? 0) + 1
                return max(0, 100 - span)
            }
        }

        return nil
    }

    private func normalize(_ value: String) -> String {
        value
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
