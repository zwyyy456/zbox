import AppKit
import AVKit
import SwiftUI

struct RecordingPreviewView: View {
    let kind: RecordingKind
    let url: URL
    let saved: URL?
    let session: RecordingSession

    var body: some View {
        VStack(spacing: 12) {
            RecordingMediaView(kind: kind, url: url)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel(kind == .video ? Text("Video Preview") : Text("GIF Preview"))

            HStack {
                if let saved {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([saved]) }
                } else {
                    Button("Discard", role: .destructive, action: session.discard)
                }
                Spacer()
                if session.isSaving { ProgressView().controlSize(.small) }
                Button("Save…", action: session.save).keyboardShortcut(.defaultAction)
            }
            .disabled(session.isSaving || session.isClosing)
        }
    }
}

private struct RecordingMediaView: NSViewRepresentable {
    let kind: RecordingKind
    let url: URL

    func makeNSView(context: Context) -> NSView {
        switch kind {
        case .video:
            let playerView = AVPlayerView()
            playerView.player = AVPlayer(url: url)
            playerView.controlsStyle = .inline
            return playerView
        case .gif:
            let imageView = NSImageView()
            imageView.imageScaling = .scaleProportionallyDown
            imageView.image = NSImage(contentsOf: url)
            imageView.animates = true
            return imageView
        }
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
