import Foundation

nonisolated enum ClipboardHistoryFilter: String, CaseIterable, Identifiable {
    case all, text, links, images, pinned
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: String(localized: "All Items")
        case .text: String(localized: "Text")
        case .links: String(localized: "Links")
        case .images: String(localized: "Images")
        case .pinned: String(localized: "Pinned")
        }
    }
    func includes(_ entry: ClipboardEntry) -> Bool {
        switch self {
        case .all: true
        case .text: entry.kind == "text"
        case .links: entry.kind == "link"
        case .images: ["png", "tiff"].contains(entry.kind)
        case .pinned: entry.pinned
        }
    }
}
