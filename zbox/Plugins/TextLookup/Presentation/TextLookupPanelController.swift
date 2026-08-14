import AppKit
import SwiftUI

@MainActor
final class TextLookupPanelController {
    private static let escapeRegistrationID = "builtin.text-lookup.dismiss"

    private let panel: TextLookupPanel
    private let hotkeyRegistrar: GlobalHotkeyRegistrar

    var isVisible: Bool { panel.isVisible }

    init(
        model: TextLookupSessionModel,
        settings: TextLookupSettingsStore,
        hotkeyRegistrar: GlobalHotkeyRegistrar
    ) {
        self.hotkeyRegistrar = hotkeyRegistrar
        let hostingView = NSHostingView(
            rootView: TextLookupPanelView(model: model, settings: settings)
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 520, height: 560)

        panel = TextLookupPanel(
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

    func show(anchor: CGRect?) {
        let resolvedAnchor = anchor ?? CGRect(
            x: NSEvent.mouseLocation.x,
            y: NSEvent.mouseLocation.y,
            width: 1,
            height: 1
        )
        let screen = NSScreen.screens.first { $0.frame.contains(resolvedAnchor.center) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }

        let width = min(520, screen.visibleFrame.width - 24)
        let size = CGSize(
            width: width,
            height: min(560, screen.visibleFrame.height - 24)
        )
        let origin = TextLookupPanelPlacement.origin(
            anchor: resolvedAnchor,
            panelSize: size,
            visibleFrame: screen.visibleFrame
        )
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
        registerEscape()
    }

    func hide() {
        hotkeyRegistrar.unregister(id: Self.escapeRegistrationID)
        panel.orderOut(nil)
    }

    private func registerEscape() {
        hotkeyRegistrar.unregister(id: Self.escapeRegistrationID)
        try? hotkeyRegistrar.register(
            id: Self.escapeRegistrationID,
            hotkey: Hotkey(keyCode: 53, modifiers: 0),
            label: "Text Lookup Escape"
        ) { [weak self] in
            self?.hide()
        }
    }
}

@MainActor
private final class TextLookupPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
