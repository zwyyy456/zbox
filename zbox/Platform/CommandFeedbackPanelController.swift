import AppKit
import SwiftUI

@MainActor
final class CommandFeedbackPanelController {
    private let panel: CommandFeedbackPanel
    private let hostingView: NSHostingView<CommandFeedbackView>
    private let onRecovery: (CommandRecoveryAction) -> Void
    private var dismissTask: Task<Void, Never>?

    init(onRecovery: @escaping (CommandRecoveryAction) -> Void) {
        self.onRecovery = onRecovery
        hostingView = NSHostingView(
            rootView: CommandFeedbackView(
                feedback: .failure("", recovery: nil),
                onRecovery: { _ in },
                onDismiss: {}
            )
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 420, height: 120)

        panel = CommandFeedbackPanel(
            contentRect: hostingView.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.animationBehavior = .utilityWindow
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
    }

    func show(_ feedback: CommandFeedback) {
        dismissTask?.cancel()
        hostingView.rootView = CommandFeedbackView(
            feedback: feedback,
            onRecovery: { [weak self] recovery in
                self?.hide()
                self?.onRecovery(recovery)
            },
            onDismiss: { [weak self] in self?.hide() }
        )

        let contentSize = hostingView.fittingSize
        panel.setContentSize(NSSize(width: 420, height: max(112, contentSize.height)))
        positionOnCurrentScreen()
        panel.orderFrontRegardless()

        guard feedback.recoveryAction == nil else { return }
        dismissTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(4))
            } catch {
                return
            }
            self?.hide()
        }
    }

    func hide() {
        dismissTask?.cancel()
        dismissTask = nil
        panel.orderOut(nil)
    }

    private func positionOnCurrentScreen() {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }

        let visibleFrame = screen.visibleFrame
        let panelSize = panel.frame.size
        panel.setFrameOrigin(
            NSPoint(
                x: visibleFrame.midX - panelSize.width / 2,
                y: visibleFrame.maxY - panelSize.height - 56
            )
        )
    }
}

@MainActor
private final class CommandFeedbackPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
