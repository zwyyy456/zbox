import Foundation

/// Secondary actions offered for application results through Command-K.
nonisolated enum RootSearchAction: Hashable, Sendable {
    case open
    case showInFinder
    case copyPath
    case quit

    var title: String {
        switch self {
        case .open: String(localized: "Open Application")
        case .showInFinder: String(localized: "Show in Finder")
        case .copyPath: String(localized: "Copy Path")
        case .quit: String(localized: "Quit Application")
        }
    }

    var systemImage: String {
        switch self {
        case .open: "arrow.up.forward.app"
        case .showInFinder: "folder"
        case .copyPath: "doc.on.doc"
        case .quit: "xmark.circle"
        }
    }
}
