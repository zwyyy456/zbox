nonisolated struct CommandFeedback: Equatable, Sendable {
    let message: String
    let recoveryAction: CommandRecoveryAction?
}

nonisolated enum CommandRecoveryAction: Equatable, Sendable {
    case openAccessibilitySettings
    case openWindowManagementSettings
}
