import AppKit
import ScreenCaptureKit

@MainActor
final class ScreenshotSelection {
    private var panels: [NSPanel] = []

    func show(mode: ScreenshotMode, windows: [SCWindow],
              selected: @escaping (NSScreen, CGRect?, SCWindow?) -> Void, cancelled: @escaping () -> Void) {
        close()
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        let orderedIDs = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []).compactMap { $0[kCGWindowNumber as String] as? CGWindowID }
        let candidates = orderedIDs.compactMap { id in windows.first { $0.windowID == id } }.filter {
            $0.owningApplication?.processID != ProcessInfo.processInfo.processIdentifier && $0.windowLayer == 0
        }
        for screen in NSScreen.screens {
            let panel = ScreenshotSelectionPanel(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.acceptsMouseMovedEvents = true
            panel.isReleasedWhenClosed = false
            let view = ScreenshotSelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.mode = mode
            view.windowFrames = candidates.map {
                ($0, ScreenshotGeometry.screenRect($0.frame, primaryHeight: primaryHeight)
                    .offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY))
            }
            view.cancel = cancelled
            view.selected = { rect, window in
                selected(screen, rect?.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY), window)
            }
            panel.contentView = view
            panels.append(panel)
            panel.orderFrontRegardless()
            if screen.frame.contains(NSEvent.mouseLocation) { panel.makeKey(); panel.makeFirstResponder(view) }
        }
    }

    func close() {
        for panel in panels { panel.orderOut(nil); panel.close() }
        panels.removeAll()
    }
}

private final class ScreenshotSelectionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private final class ScreenshotSelectionView: NSView {
    var mode = ScreenshotMode.area
    var windowFrames: [(SCWindow, CGRect)] = []
    var selected: ((CGRect?, SCWindow?) -> Void)?
    var cancel: (() -> Void)?
    private var anchor: CGPoint?
    private var selection: CGRect?
    private var hoveredWindow: SCWindow?
    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { cancel?() } else { super.keyDown(with: event) }
    }
    override func rightMouseDown(with event: NSEvent) { cancel?() }
    override func mouseMoved(with event: NSEvent) {
        guard mode == .window else { return }
        let point = convert(event.locationInWindow, from: nil)
        let match = windowFrames.first { $0.1.contains(point) }
        hoveredWindow = match?.0
        selection = match?.1.intersection(bounds)
        needsDisplay = true
    }
    override func mouseDown(with event: NSEvent) {
        if mode == .window { mouseMoved(with: event); return }
        anchor = convert(event.locationInWindow, from: nil)
    }
    override func mouseDragged(with event: NSEvent) {
        guard let anchor, mode == .area else { return }
        let end = convert(event.locationInWindow, from: nil)
        selection = CGRect(x: min(anchor.x, end.x), y: min(anchor.y, end.y),
                           width: abs(end.x - anchor.x), height: abs(end.y - anchor.y)).intersection(bounds)
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        if mode == .window {
            if let hoveredWindow { selected?(nil, hoveredWindow) }
        } else {
            mouseDragged(with: event)
            if let selection, selection.width >= 1, selection.height >= 1 { selected?(selection, nil) }
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        let shade = NSBezierPath(rect: bounds)
        if let selection { shade.appendRect(selection) }
        shade.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.3).setFill()
        shade.fill()
        if let selection {
            NSColor.white.setStroke()
            let border = NSBezierPath(rect: selection)
            border.lineWidth = 2
            border.stroke()
        }
        let hint = mode == .window ? String(localized: "Click a window · Esc to cancel")
            : String(localized: "Drag to select an area · Esc to cancel")
        (hint as NSString).draw(at: CGPoint(x: 24, y: bounds.height - 48), withAttributes: [
            .font: NSFont.systemFont(ofSize: 16, weight: .medium), .foregroundColor: NSColor.white,
        ])
    }
}
