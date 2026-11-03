import AppKit

nonisolated struct ClipboardPayload: Sendable {
    let kind: String
    let text: String
    let data: Data
    let sourceBundleID: String?
}

nonisolated enum ClipboardHistoryError: LocalizedError, Equatable {
    case accessRequired, unsupported, tooLarge, changed, storageFull

    var errorDescription: String? {
        switch self {
        case .accessRequired: String(localized: "Allow clipboard access in System Settings, then resume recording.")
        case .unsupported: String(localized: "The last clipboard item uses an unsupported format.")
        case .tooLarge: String(localized: "The last clipboard item is too large to save.")
        case .changed: String(localized: "The clipboard changed while it was being read.")
        case .storageFull: String(localized: "Pinned items fill the history. Unpin or delete an item to continue recording.")
        }
    }
}

@MainActor
enum ClipboardReader {
    static let textLimit = 1_024 * 1_024

    static func checkAccess(_ pasteboard: NSPasteboard) throws {
        if #available(macOS 15.4, *), pasteboard.accessBehavior != .alwaysAllow {
            throw ClipboardHistoryError.accessRequired
        }
    }

    static func read(
        from pasteboard: NSPasteboard,
        excluding excluded: Set<String>,
        sourceBundleID: String?
    ) throws -> ClipboardPayload? {
        try checkAccess(pasteboard)
        let count = pasteboard.changeCount
        let types = Set((pasteboard.types ?? []).map(\.rawValue))
        guard types.isDisjoint(with: ClipboardContentPolicy.ignoredTypes) else { return nil }
        let declaredSource = pasteboard.string(forType: .init("org.nspasteboard.source"))
        guard ![sourceBundleID, declaredSource].compactMap({ $0 }).contains(where: excluded.contains) else {
            return nil
        }
        guard let items = pasteboard.pasteboardItems, items.count == 1,
              !types.contains(NSPasteboard.PasteboardType.fileURL.rawValue) else {
            throw ClipboardHistoryError.unsupported
        }
        for type in [NSPasteboard.PasteboardType.png, .tiff] where types.contains(type.rawValue) {
            guard let data = pasteboard.data(forType: type) else { throw ClipboardHistoryError.unsupported }
            let (width, height) = try ClipboardImage.dimensions(of: data)
            guard count == pasteboard.changeCount else { throw ClipboardHistoryError.changed }
            return ClipboardPayload(kind: type == .png ? "png" : "tiff",
                text: String(localized: "Image") + " (\(width) × \(height))", data: data,
                sourceBundleID: declaredSource?.isEmpty == false ? declaredSource : sourceBundleID)
        }
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else {
            throw ClipboardHistoryError.unsupported
        }
        let data = Data(text.utf8)
        guard data.count <= textLimit else { throw ClipboardHistoryError.tooLarge }
        guard count == pasteboard.changeCount else { throw ClipboardHistoryError.changed }
        let url = URL(string: text)
        let isLink = ["https", "http"].contains(url?.scheme?.lowercased() ?? "") && url?.host != nil
        return ClipboardPayload(kind: isLink ? "link" : "text", text: text, data: data,
                                sourceBundleID: declaredSource?.isEmpty == false ? declaredSource : sourceBundleID)
    }
}
