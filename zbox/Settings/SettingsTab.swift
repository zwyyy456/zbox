import Foundation

nonisolated enum SettingsTab: Hashable {
    case display
    case workspace
    case general
    case shortcuts
    case windowManagement
    case textLookup
    case screenshot
    case clipboardHistory

    var title: String {
        switch self {
        case .display: String(localized: "Display")
        case .workspace: String(localized: "Workspace")
        case .general: String(localized: "General")
        case .shortcuts: String(localized: "Shortcuts")
        case .windowManagement: String(localized: "Window Management")
        case .textLookup: String(localized: "Text Lookup")
        case .screenshot: String(localized: "Screenshot")
        case .clipboardHistory: String(localized: "Clipboard History")
        }
    }

    var systemImage: String {
        switch self {
        case .display: "display"
        case .workspace: "rectangle.3.group"
        case .general: "gearshape"
        case .shortcuts: "keyboard"
        case .windowManagement: "macwindow"
        case .textLookup: "text.magnifyingglass"
        case .screenshot: "camera.viewfinder"
        case .clipboardHistory: "clipboard"
        }
    }
}
