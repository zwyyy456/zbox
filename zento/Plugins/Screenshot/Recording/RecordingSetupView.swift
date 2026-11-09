import SwiftUI

struct RecordingWindowView: View {
    @Bindable var session: RecordingSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
            if let status = session.status {
                Text(status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(width: 320, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .padding(10)
        .fixedSize()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { session.updateControlSize($0) }
        .background {
            RoundedRectangle(cornerRadius: 12).fill(.regularMaterial)
                .gesture(WindowDragGesture())
        }
        .onExitCommand { session.requestClose() }
    }

    @ViewBuilder private var content: some View {
        switch session.state {
        case .selecting:
            RecordingSetupView(session: session)
        case .countdown(let seconds):
            HStack(spacing: 16) {
                Text("Recording starts in \(seconds)").monospacedDigit()
                Button("Cancel", action: session.discard)
                if session.kind == .gif {
                    Button("Start Now", action: session.startImmediately)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .frame(minHeight: 32)
        case .starting, .recording, .finishing, .discarding:
            RecordingControlPanel(session: session)
        case .preview:
            Text("Recording Complete").frame(minHeight: 32)
        case .failed(let reason):
            Text(reason).frame(width: 320, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Button("Close", action: session.discard)
                .keyboardShortcut(.defaultAction)
        case .closed:
            EmptyView()
        }
    }

}

private struct RecordingSetupView: View {
    @Bindable var session: RecordingSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button(action: session.requestClose) {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .frame(width: 24, height: 32)
                .help("Close")
                .accessibilityLabel(Text("Close"))

                Divider().frame(height: 24)
                ForEach(RecordingTargetKind.allCases, id: \.self) { kind in
                    Button { session.targetKind = kind } label: {
                        Image(systemName: symbol(for: kind))
                            .font(.system(size: 20))
                            .frame(width: 40, height: 32)
                            .contentShape(Rectangle())
                            .background {
                                if session.targetKind == kind {
                                    RoundedRectangle(cornerRadius: 6).fill(.primary.opacity(0.12))
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .help(kind.title)
                    .accessibilityLabel(kind.title)
                    .accessibilityAddTraits(session.targetKind == kind ? .isSelected : [])
                }
                Divider().frame(height: 24)
                Button { session.choose(session.targetKind) } label: {
                    Text("Record")
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background(Color.accentColor,
                                    in: RoundedRectangle(cornerRadius: 6))
                        .foregroundStyle(Color.white)
                }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
                Menu("Options") {
                    if session.kind == .gif {
                        Picker("Recording Start", selection: $session.options.selectedStartDelay) {
                            ForEach(RecordingStartDelay.allCases, id: \.self) { delay in
                                Text(delay.title).tag(delay)
                            }
                        }
                    }
                    if session.kind == .video {
                        Picker("Video Codec", selection: $session.options.selectedVideoCodec) {
                            ForEach(RecordingVideoCodec.allCases, id: \.self) { codec in
                                Text(codec.title).tag(codec)
                            }
                        }
                    }
                    Picker("Frame rate", selection: $session.options.frameRate) {
                        ForEach(session.kind.frameRates, id: \.self) { rate in
                            Text("\(rate) fps").tag(rate)
                        }
                    }
                    Picker("Scale", selection: $session.options.scale) {
                        ForEach(RecordingOptions.scales, id: \.self) { scale in
                            if scale == 100 { Text("Original Size").tag(scale) }
                            else { Text(Double(scale) / 100, format: .percent).tag(scale) }
                        }
                    }
                    if session.kind == .video && session.targetKind == .window && session.options.capturesAudio {
                        Text("Audio can include other windows from the selected app.")
                    }
                    Divider()
                    Toggle("Show Pointer", isOn: $session.options.showsCursor)
                    if session.kind == .video {
                        Toggle("Record System Audio", isOn: $session.options.capturesAudio)
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .frame(height: 32)
            }
            .fixedSize()


        }
        .font(.callout)
    }

    private func symbol(for kind: RecordingTargetKind) -> String {
        switch kind {
        case .display: "display"
        case .window: "macwindow"
        case .region: "rectangle.dashed"
        }
    }
}
