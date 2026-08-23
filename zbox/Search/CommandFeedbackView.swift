import SwiftUI

struct CommandFeedbackView: View {
    let feedback: CommandFeedback
    let onRecovery: (CommandRecoveryAction) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Command Failed", systemImage: "exclamationmark.triangle")
                .font(.headline)

            Text(feedback.message)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                if let recovery = feedback.recoveryAction {
                    switch recovery {
                    case .openAccessibilitySettings:
                        Button("Open Accessibility Settings") {
                            onRecovery(recovery)
                        }
                    case .openWindowManagementSettings:
                        Button("Open Window Management") {
                            onRecovery(recovery)
                        }
                    }
                }

                Spacer()
                Button("Dismiss", action: onDismiss)
            }
        }
        .padding(16)
        .frame(width: 420)
        .background(.regularMaterial)
        .clipShape(.rect(cornerRadius: 12))
        .accessibilityElement(children: .contain)
    }
}
