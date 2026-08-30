nonisolated struct CommandFeedback: Equatable, Sendable {
    let message: String
    let recoveryAction: CommandRecoveryAction?
}
