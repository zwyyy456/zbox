import Foundation

/// Command configuration and application actions offered through Command-K.
nonisolated enum RootSearchAction: Hashable, Sendable {
    case editAlias
    case open
    case showInFinder
    case copyPath
    case quit

    var title: String {
        switch self {
        case .editAlias: String(localized: "Edit Alias…")
        case .open: String(localized: "Open Application")
        case .showInFinder: String(localized: "Show in Finder")
        case .copyPath: String(localized: "Copy Path")
        case .quit: String(localized: "Quit Application")
        }
    }

    var systemImage: String {
        switch self {
        case .editAlias: "text.cursor"
        case .open: "arrow.up.forward.app"
        case .showInFinder: "folder"
        case .copyPath: "doc.on.doc"
        case .quit: "xmark.circle"
        }
    }
}
