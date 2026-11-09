import SwiftUI

struct RecordingWindowView: View {
    @Bindable var session: RecordingSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if session.isConfirmingClose {
                closeConfirmation
            } else {
                content
                if let status = session.status {
                    Text(status)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .accessibilityAddTraits(.updatesFrequently)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onExitCommand {
            if session.isConfirmingClose { session.decideClose(.cancel) }
            else { session.requestClose() }
        }
    }

    @ViewBuilder private var content: some View {
        switch session.state {
        case .selecting:
            Text("Choose what to record").font(.headline)
            HStack {
                ForEach(RecordingTargetKind.allCases, id: \.self) { kind in
                    Button(kind.title) { session.choose(kind) }
                }
            }
        case .ready(let target):
            RecordingSetupView(kind: session.kind, target: target, options: $session.options,
                               reselect: session.chooseAgain, start: session.start)
        case .countdown(let seconds):
            HStack {
                Text("Recording starts in \(seconds)").monospacedDigit()
                Spacer()
                Button("Cancel", action: session.discard)
            }
        case .starting, .recording, .finishing, .converting, .discarding:
            RecordingControlPanel(session: session)
        case .preview(let url, let saved):
            RecordingPreviewView(kind: session.kind, url: url, saved: saved, session: session)
        case .failed(let reason):
            Text(reason)
            Button("Close", action: session.discard)
                .keyboardShortcut(.defaultAction)
        case .closed:
            EmptyView()
        }
    }

    private var closeConfirmation: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save the recording before closing?").font(.headline)
            HStack {
                Button("Cancel") { session.decideClose(.cancel) }.keyboardShortcut(.cancelAction)
                Button("Discard", role: .destructive) { session.decideClose(.discard) }
                Spacer()
                Button(saveTitle) { session.decideClose(.save) }.keyboardShortcut(.defaultAction)
            }
        }
    }

    private var saveTitle: String {
        switch session.state {
        case .starting, .recording: String(localized: "Stop & Save")
        default: String(localized: "Save…")
        }
    }
}

private struct RecordingSetupView: View {
    let kind: RecordingKind
    let target: RecordingTarget
    @Binding var options: RecordingOptions
    let reselect: () -> Void
    let start: () -> Void

    var body: some View {
        let size = options.outputSize(for: target.pixelSize)
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(target.name).font(.headline).lineLimit(1).help(target.name)
                Text("\(Int(size.width)) × \(Int(size.height)) px · \(options.frameRate) fps · \(kind.format)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Form {
                Picker("Frame rate", selection: $options.frameRate) {
                    ForEach(kind.frameRates, id: \.self) { rate in
                        Text("\(rate) fps").tag(rate)
                    }
                }
                Picker("Scale", selection: $options.scale) {
                    ForEach(RecordingOptions.scales, id: \.self) { scale in
                        if scale == 100 { Text("Original Size").tag(scale) }
                        else { Text(Double(scale) / 100, format: .percent).tag(scale) }
                    }
                }
                Toggle("Show Pointer", isOn: $options.showsCursor)
                if kind == .video {
                    Toggle("Record System Audio", isOn: $options.capturesAudio)
                    if target.kind == .window {
                        Text("Audio can include other windows from the selected app.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("GIF recording stops automatically after 30 seconds.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.columns)
            Spacer(minLength: 0)
            HStack {
                Button("Choose Again", action: reselect)
                Spacer()
                Button("Start Recording", action: start).keyboardShortcut(.defaultAction)
            }
        }
    }
}
