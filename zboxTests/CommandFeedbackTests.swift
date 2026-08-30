import Foundation
import Testing
@testable import zbox

struct CommandFeedbackTests {
    @Test
    func permissionFailureOffersAccessibilityRecovery() {
        let feedback = CommandFeedbackMapper.failure(for: AccessibilityWindowError.permissionRequired)

        #expect(
            feedback == CommandFeedback(
                message: AccessibilityWindowError.permissionRequired.localizedDescription,
                recoveryAction: .openAccessibilitySettings
            )
        )
    }

    @Test
    func ordinaryFailureHasNoRecoveryAction() {
        let feedback = CommandFeedbackMapper.failure(for: TestFailure())

        #expect(feedback == CommandFeedback(message: "Command failed.", recoveryAction: nil))
    }

    @Test
    func disabledWindowManagementOffersSettingsRecovery() {
        let feedback = CommandFeedbackMapper.failure(for: WindowManagementError.disabled)

        #expect(
            feedback == CommandFeedback(
                message: WindowManagementError.disabled.localizedDescription,
                recoveryAction: .openWindowManagementSettings
            )
        )
    }
}

private struct TestFailure: LocalizedError {
    var errorDescription: String? { "Command failed." }
}
