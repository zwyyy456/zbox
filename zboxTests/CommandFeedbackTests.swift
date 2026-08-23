import Foundation
import Testing
@testable import zbox

struct CommandFeedbackTests {
    @Test
    func permissionFailureOffersAccessibilityRecovery() {
        let feedback = CommandFeedbackMapper.failure(for: AccessibilityWindowError.permissionRequired)

        #expect(
            feedback == .failure(
                AccessibilityWindowError.permissionRequired.localizedDescription,
                recovery: .openAccessibilitySettings
            )
        )
    }

    @Test
    func ordinaryFailureHasNoRecoveryAction() {
        let feedback = CommandFeedbackMapper.failure(for: TestFailure())

        #expect(feedback == .failure("Command failed.", recovery: nil))
    }

    @Test
    func disabledWindowManagementOffersSettingsRecovery() {
        let feedback = CommandFeedbackMapper.failure(for: WindowManagementError.disabled)

        #expect(
            feedback == .failure(
                WindowManagementError.disabled.localizedDescription,
                recovery: .openWindowManagementSettings
            )
        )
    }
}

private struct TestFailure: LocalizedError {
    var errorDescription: String? { "Command failed." }
}
