import Foundation

nonisolated struct CommandID: Hashable, Sendable {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

nonisolated enum CommandSearchAliasKind: Sendable {
    case transliteration
    case initials
}

nonisolated struct CommandSearchAlias: Sendable {
    let value: String
    let kind: CommandSearchAliasKind
}

nonisolated struct CommandDescriptor: Identifiable, Sendable {
    let id: CommandID
    let title: String
    /// Plugin or feature name shown beside the result; nil for applications.
    let category: String?
    let subtitle: String?
    let keywords: [String]
    let systemImage: String?
    let searchAliases: [CommandSearchAlias]

    init(
        systemImage: String? = nil,
        id: CommandID,
        title: String,
        category: String? = nil,
        subtitle: String?,
        keywords: [String],
        searchAliases: [CommandSearchAlias] = []
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.subtitle = subtitle
        self.keywords = keywords
        self.systemImage = systemImage
        self.searchAliases = searchAliases
    }
}

nonisolated enum CommandSource: Sendable {
    case rootSearch
    case directHotkey
}

nonisolated struct CommandContext: Sendable {
    let source: CommandSource
    let frontmostApplicationPID: Int32?
}

nonisolated struct CommandShortcutTarget: Identifiable, Sendable {
    let id: CommandID
    let title: String
}
