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
                HStack(spacing: 16) {
                    HStack(spacing: 8) {
                        Image(systemName: "record.circle.fill").foregroundStyle(.red)
                        Text(Duration.seconds(elapsed).formatted(.time(pattern: .minuteSecond)))
                            .monospacedDigit()
                            .frame(minWidth: 46, alignment: .leading)
                        if session.kind == .gif {
                            Text("\(max(0, Int64(RecordingOptions.gifLimit) - elapsed)) s remaining")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .fixedSize()
                        }
                    }
                    Button("Stop Recording", action: session.stopRecording)
                        .buttonStyle(.borderedProminent)
                    Button("Cancel", action: session.discard)
                }
                .frame(minHeight: 32)
                .fixedSize()
                .disabled(session.isClosing)
            }
        case .finishing:
            ProgressView("Finishing Recording…").controlSize(.small).frame(minHeight: 32)
        case .discarding:
            ProgressView("Discarding Recording…").controlSize(.small).frame(minHeight: 32)
        default:
            EmptyView()
        }
    }

    private func controls(_ title: String, canStop: Bool) -> some View {
        HStack(spacing: 16) {
            Text(title).monospacedDigit()
            Button("Stop Recording", action: session.stopRecording).disabled(!canStop)
            Button("Cancel", action: session.discard)
        }
        .frame(minHeight: 32)
        .disabled(session.isClosing)
    }
}
