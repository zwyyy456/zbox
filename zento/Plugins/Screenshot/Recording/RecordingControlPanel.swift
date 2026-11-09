import SwiftUI

struct RecordingControlPanel: View {
    let session: RecordingSession

    var body: some View {
        switch session.state {
        case .starting:
            controls("Starting Recording…", canStop: false)
        case .recording(let start):
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                let elapsed = max(0, start.duration(to: .now).components.seconds)
                VStack(alignment: .leading, spacing: 8) {
                    controls(Duration.seconds(elapsed).formatted(.time(pattern: .minuteSecond)), canStop: true)
                    if session.kind == .gif {
                        let remaining = max(0, Int64(RecordingOptions.gifLimit) - elapsed)
                        Text("\(remaining) s remaining")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
        case .finishing:
            ProgressView("Finishing Recording…").controlSize(.small)
        case .converting(let progress):
            VStack(alignment: .trailing, spacing: 12) {
                ProgressView("Converting GIF…", value: progress)
                Button("Cancel", action: session.discard).disabled(session.isClosing)
            }
        case .discarding:
            ProgressView("Discarding Recording…").controlSize(.small)
        default:
            EmptyView()
        }
    }

    private func controls(_ title: String, canStop: Bool) -> some View {
        HStack {
            Text(title).monospacedDigit()
            Spacer()
            Button("Stop Recording", action: session.stopRecording).disabled(!canStop)
            Button("Cancel", action: session.discard)
        }
        .disabled(session.isClosing)
    }
}
