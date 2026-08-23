nonisolated enum SettingsTab: Hashable {
    case general
    case shortcuts
    case windowManagement
    case textLookup

    var title: String {
        switch self {
        case .general: "General"
        case .shortcuts: "Shortcuts"
        case .windowManagement: "Window Management"
        case .textLookup: "Text Lookup"
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
