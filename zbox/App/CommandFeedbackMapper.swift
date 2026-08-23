import Foundation

nonisolated enum CommandFeedbackMapper {
    static func failure(for error: any Error) -> CommandFeedback {
        let recovery: CommandRecoveryAction? = if error as? AccessibilityWindowError == .permissionRequired {
            .openAccessibilitySettings
        } else {
            nil
        }
        return .failure(error.localizedDescription, recovery: recovery)
    }
}
