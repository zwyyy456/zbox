import AppKit

nonisolated enum ScreenshotLinkFormat: String, CaseIterable, Identifiable {
    case url, markdown
    var id: String { rawValue }
    var title: String { self == .url ? "URL" : "Markdown" }
    func text(for url: URL) -> String {
        self == .url ? url.absoluteString : "![Screenshot](<\(url.absoluteString)>)"
    }
}

@MainActor
enum ScreenshotClipboard {
    /// Check and write in one Main Actor turn; an intervening user copy always wins.
    @discardableResult
    static func copyLink(_ url: URL, format: ScreenshotLinkFormat, to board: NSPasteboard,
                         coordinator: ClipboardAccessCoordinator, ifUnchangedSince count: Int? = nil) -> Bool {
        if let count, board.changeCount != count { return false }
        board.prepareForNewContents(with: .currentHostOnly)
        defer { coordinator.didWrite(changeCount: board.changeCount) }
        return board.setString(format.text(for: url), forType: .string)
    }
}
