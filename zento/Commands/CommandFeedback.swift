import Foundation

nonisolated struct CommandFeedback: Equatable, Sendable {
    let message: String
    let recoveryAction: CommandRecoveryAction?
}

nonisolated enum CommandRecoveryAction: Equatable, Sendable {
    case openDisplaySettings
    case openWorkspaceSettings
    case openAccessibilitySettings
    case openWindowManagementSettings
}

extension CommandRecoveryAction {
    var title: String {
        switch self {
        case .openAccessibilitySettings: String(localized: "Open Accessibility Settings")
        case .openDisplaySettings: String(localized: "Open Display Settings")
        case .openWorkspaceSettings: String(localized: "Open Workspace Settings")
        case .openWindowManagementSettings: String(localized: "Open Window Management")
        }
    }
}
