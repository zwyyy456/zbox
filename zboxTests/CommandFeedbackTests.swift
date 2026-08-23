import Foundation
import Testing
@testable import zbox

struct CommandFeedbackTests {
    @Test
    func permissionFailureOffersAccessibilityRecovery() {
        let feedback = CommandFeedbackMapper.failure(for: AccessibilityWindowError.permissionRequired)

        #expect(
            feedback == .failure(
                "Accessibility permission is required to move windows.",
                recovery: .openAccessibilitySettings
            )
        )
    }

    @Test
    func ordinaryFailureHasNoRecoveryAction() {
        let feedback = CommandFeedbackMapper.failure(for: TestFailure())

        #expect(feedback == .failure("Command failed.", recovery: nil))
    }
}

private struct TestFailure: LocalizedError {
    var errorDescription: String? { "Command failed." }
}
