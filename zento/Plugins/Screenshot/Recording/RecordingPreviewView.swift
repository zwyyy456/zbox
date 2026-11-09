import AppKit
import AVKit
import SwiftUI

nonisolated enum RecordingPreviewLayout {
    static func naturalSize(pixels: CGSize, captureScale: CGFloat) -> CGSize {
        CGSize(width: pixels.width / captureScale, height: pixels.height / captureScale)
    }

    static func fittedImageSize(natural: CGSize, available: CGSize) -> CGSize {
        let scale = min(1, max(0, available.width) / natural.width, max(0, available.height) / natural.height)
        return CGSize(width: natural.width * scale, height: natural.height * scale)
    }

    static func initialContentSize(natural: CGSize, footer: CGSize, available: CGSize) -> CGSize {
        let image = fittedImageSize(natural: natural,
                                    available: CGSize(width: available.width, height: available.height - footer.height))
        return CGSize(width: image.width,
                      height: image.height + footer.height)
    }
}

struct RecordingPreviewView: View {
    let session: RecordingSession

    var body: some View {
        if case .preview(let url, let saved) = session.state {
            VStack(spacing: 0) {
                GeometryReader { geometry in
                    let size = RecordingPreviewLayout.fittedImageSize(natural: session.previewNaturalSize,
                                                                       available: geometry.size)
                    RecordingMediaView(kind: session.kind, url: url, naturalSize: session.previewNaturalSize)
                        .frame(width: size.width, height: size.height)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityLabel(session.kind == .video ? Text("Video Preview") : Text("GIF Preview"))
                }
                .frame(minWidth: 0, minHeight: 0)
                .layoutPriority(1)
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 16) {
                            metadata
                            Spacer(minLength: 0)
                            actions(saved: saved)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            metadata
                            actions(saved: saved)
                        }
                        Menu {
                            metadata
                            actionButtons(saved: saved)
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                    .disabled(session.isSaving || session.isClosing)
                    if let status = session.status {
                        Text(status).font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGSize.self) { $0.size } action: {
                    session.updatePreviewFooterSize($0)
                }
            }
        }
    }

    private var metadata: some View {
        Text("\(Int(session.previewPixelSize.width)) × \(Int(session.previewPixelSize.height)) px")
            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            .fixedSize()
    }

    private func actions(saved: URL?) -> some View {
        HStack(spacing: 8) {
            if session.isSaving { ProgressView().controlSize(.small) }
            actionButtons(saved: saved)
        }
        .fixedSize()
    }

    @ViewBuilder private func actionButtons(saved: URL?) -> some View {
        if let saved {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([saved]) }
        } else {
            Button("Discard", role: .destructive, action: session.discard)
        }
        Button("Save…", action: session.save)
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
    }
}

private struct RecordingMediaView: NSViewRepresentable {
    let kind: RecordingKind
    let url: URL
    let naturalSize: CGSize

    func makeNSView(context: Context) -> NSView {
        switch kind {
        case .video:
            let playerView = AVPlayerView()
            playerView.player = AVPlayer(url: url)
            playerView.controlsStyle = .inline
            playerView.videoGravity = .resizeAspect
            return playerView
        case .gif:
            let imageView = NSImageView()
            imageView.imageScaling = .scaleProportionallyDown
            let image = NSImage(contentsOf: url)
            image?.size = naturalSize
            imageView.image = image
            imageView.animates = true
            return imageView
        }
    }

    // The canvas owns sizing. A GIF's pixel dimensions must never become the window's minimum size.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? naturalSize.width, height: proposal.height ?? naturalSize.height)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        (nsView as? AVPlayerView)?.player?.pause()
    }
}
