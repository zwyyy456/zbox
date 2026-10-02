import Foundation

nonisolated enum CommandFeedbackMapper {
    static func failure(for error: any Error) -> CommandFeedback {
        let recovery: CommandRecoveryAction?
        switch error {
        case AccessibilityWindowError.permissionRequired:
            recovery = .openAccessibilitySettings
        case is DisplayError:
            recovery = .openDisplaySettings
        case WorkspaceError.disabled:
            recovery = .openWorkspaceSettings
        case WindowManagementError.disabled:
            recovery = .openWindowManagementSettings
        default:
            recovery = nil
        }
        return CommandFeedback(
            message: error.localizedDescription,
            recoveryAction: recovery
        )
    }
}
