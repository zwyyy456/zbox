import Foundation

nonisolated enum CommandFeedbackMapper {
    static func failure(for error: any Error) -> CommandFeedback {
        let recovery: CommandRecoveryAction?
        switch error {
        case AccessibilityWindowError.permissionRequired:
            recovery = .openAccessibilitySettings
        case WindowManagementError.disabled:
            recovery = .openWindowManagementSettings
        default:
            recovery = nil
        }
        return .failure(error.localizedDescription, recovery: recovery)
    }
}
