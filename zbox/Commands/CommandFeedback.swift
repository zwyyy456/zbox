nonisolated enum CommandFeedback: Equatable, Sendable {
    case success(String)
    case failure(String, recovery: CommandRecoveryAction?)

    var message: String {
        switch self {
        case .success(let message), .failure(let message, _):
            message
        }
    }

    var recoveryAction: CommandRecoveryAction? {
        guard case .failure(_, let recovery) = self else { return nil }
        return recovery
    }
}
