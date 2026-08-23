import Foundation

nonisolated enum SettingsTab: Hashable {
    case general
    case shortcuts
    case windowManagement
    case textLookup

    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .shortcuts: String(localized: "Shortcuts")
        case .windowManagement: String(localized: "Window Management")
        case .textLookup: String(localized: "Text Lookup")
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .shortcuts: "keyboard"
        case .windowManagement: "macwindow"
        case .textLookup: "text.magnifyingglass"
        }
    }
}
