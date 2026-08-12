import Foundation

nonisolated struct CommandID: Hashable, Sendable {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

nonisolated struct CommandDescriptor: Identifiable, Sendable {
    let id: CommandID
    let title: String
    let subtitle: String?
    let keywords: [String]
}

nonisolated enum CommandSource: Sendable {
    case rootSearch
    case directHotkey
}

nonisolated struct CommandContext: Sendable {
    let source: CommandSource
    let frontmostApplicationPID: Int32?
}
