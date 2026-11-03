import AppKit

@MainActor
enum WindowPresentation {
    static func present(_ window: NSWindow) {
        if window.isMiniaturized { window.deminiaturize(nil) }
        // Activation raises the main and key windows. Select the requested window first.
        window.makeKeyAndOrderFront(nil)
        window.makeMain()
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
    }
}

/// Keyboard-driven, nonactivating command surfaces share one focus lifecycle.
@MainActor
class TransientPanel: NSPanel {
    var dismissAfterFocusLoss: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func presentTransient() {
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        hidesOnDeactivate = false
        level = .floating
        if isMiniaturized { deminiaturize(nil) }
        makeKeyAndOrderFront(nil)
        orderFrontRegardless()
        contentView?.layoutSubtreeIfNeeded()
        if let field = editableField(in: contentView) { makeFirstResponder(field) }
    }

    private func editableField(in view: NSView?) -> NSTextField? {
        guard let view else { return nil }
        if let field = view as? NSTextField, field.isEditable, field.isEnabled { return field }
        for child in view.subviews {
            if let field = editableField(in: child) { return field }
        }
        return nil
    }

    override func resignKey() {
        super.resignKey()
        // Let child-window/sheet transitions and intentional orderOut during paste finish.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isVisible else { return }
            var root: NSWindow = self
            while let parent = root.parent { root = parent }
            guard !self.containsFocus(root) else { return }
            self.dismissAfterFocusLoss?()
        }
    }

    private func containsFocus(_ window: NSWindow) -> Bool {
        window.isKeyWindow || window.attachedSheet != nil
            || (window.childWindows ?? []).contains(where: containsFocus)
    }
}
