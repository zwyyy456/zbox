import Foundation

nonisolated enum SettingsTab: Hashable {
    case appMenu
    case audio
    case scriptCommands
    case fileSearch
    case snippets
    case quicklinks
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
        case .appMenu: String(localized: "Application Menu")
        case .audio: String(localized: "Audio")
        case .scriptCommands: String(localized: "Script Commands")
        case .fileSearch: String(localized: "File Search")
        case .snippets: String(localized: "Snippets")
        case .quicklinks: String(localized: "Quicklinks")
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
        case .appMenu: "menubar.rectangle"
        case .audio: "speaker.wave.2"
        case .scriptCommands: "terminal"
        case .fileSearch: "doc.text.magnifyingglass"
        case .snippets: "text.quote"
        case .quicklinks: "link"
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
