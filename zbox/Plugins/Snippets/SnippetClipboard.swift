import AppKit

@MainActor enum SnippetClipboard {
    static func read(from board: NSPasteboard = .general) throws -> String {
        if #available(macOS 15.4, *), board.accessBehavior == .alwaysDeny {
            throw SnippetClipboardError.accessRequired
        }
        let count = board.changeCount
        let types = Set((board.types ?? []).map(\.rawValue))
        guard types.isDisjoint(with: ClipboardContentPolicy.ignoredTypes) else { throw SnippetClipboardError.privateContent }
        guard !types.contains(NSPasteboard.PasteboardType.fileURL.rawValue),
              let text = board.string(forType: .string), !text.isEmpty else {
            throw SnippetClipboardError.noText
        }
        guard text.utf8.count <= 1_024 * 1_024 else { throw SnippetClipboardError.tooLarge }
        guard count == board.changeCount else { throw SnippetClipboardError.changed }
        return text
    }
}

nonisolated enum SnippetClipboardError: LocalizedError {
    case accessRequired, privateContent, noText, tooLarge, changed
    var errorDescription: String? {
        switch self {
        case .accessRequired: String(localized: "Allow clipboard access in System Settings to use the clipboard variable.")
        case .privateContent: String(localized: "The clipboard is marked private or temporary and cannot be inserted into a snippet.")
        case .noText: String(localized: "The clipboard does not contain available plain text.")
        case .tooLarge: String(localized: "The clipboard text exceeds the 1 MiB limit.")
        case .changed: String(localized: "The clipboard changed. Execute the snippet again.")
        }
    }
}
