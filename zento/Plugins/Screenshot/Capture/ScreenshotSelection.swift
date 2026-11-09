import AppKit
import ScreenCaptureKit
import OSLog

@MainActor
final class ScreenshotSelection {
    private let logger = Logger(subsystem: "tech.hyperseek.zento", category: "ScreenshotSelection")
    private var panels: [NSPanel] = []

    func show(mode: ScreenshotMode, windows: [SCWindow],
              selected: @escaping (NSScreen, CGRect?, SCWindow?) -> Void, cancelled: @escaping () -> Void) {
        close()
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        let orderedIDs = (CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)
            as? [[String: Any]] ?? []).compactMap { $0[kCGWindowNumber as String] as? CGWindowID }
        let candidates = orderedIDs.compactMap { id in windows.first { $0.windowID == id } }
        logger.info("selection-start mode=\(mode.rawValue, privacy: .public) shareable=\(windows.count) onscreen=\(orderedIDs.count) candidates=\(candidates.count) screens=\(NSScreen.screens.count)")
        for screen in NSScreen.screens {
            let panel = ScreenshotSelectionPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
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
            view.updateHoveredTarget(at: view.convert(panel.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil))
            panels.append(panel)
            panel.orderFrontRegardless()
            if screen.frame.contains(NSEvent.mouseLocation) { panel.makeKey(); panel.makeFirstResponder(view) }
        }
    }

    func finishChoosing() {
        for panel in panels {
            (panel.contentView as? ScreenshotSelectionView)?.finishChoosing()
            panel.ignoresMouseEvents = true
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

final class ScreenshotSelectionView: NSView {
    private static let logger = Logger(subsystem: "tech.hyperseek.zento", category: "ScreenshotSelection")
    private static let cameraCursor: NSCursor = {
        let symbol = NSImage(systemSymbolName: "camera.fill", accessibilityDescription: nil)!
            .withSymbolConfiguration(.init(paletteColors: [.black]))!
        let image = NSImage(size: NSSize(width: 28, height: 24), flipped: false) { rect in
            let outline = symbol.withSymbolConfiguration(.init(paletteColors: [.white]))!
            let glyphRect = rect.insetBy(dx: 3, dy: 3)
            for x in [-1.0, 0, 1.0] {
                for y in [-1.0, 0, 1.0] {
                    outline.draw(in: glyphRect.offsetBy(dx: x, dy: y))
                }
            }
            symbol.draw(in: glyphRect)
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: 14, y: 12))
    }()
    var mode = ScreenshotMode.area
    var windowFrames: [(SCWindow, CGRect)] = []
    var selected: ((CGRect?, SCWindow?) -> Void)?
    var cancel: (() -> Void)?
    private var isChoosing = true
    private var anchor: CGPoint?
    private var selection: CGRect?
    private var hoveredWindow: SCWindow?
    private var mouseTracking: NSTrackingArea?
    func finishChoosing() {
        selected = nil
        isChoosing = false
        if mode == .scrolling {
            needsDisplay = true
            displayIfNeeded()
        }
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let mouseTracking { removeTrackingArea(mouseTracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        mouseTracking = area
    }

    private var selectionCursor: NSCursor { (mode == .window || mode == .screen) ? Self.cameraCursor : .crosshair }
    override func resetCursorRects() { addCursorRect(bounds, cursor: selectionCursor) }
    override func cursorUpdate(with event: NSEvent) { selectionCursor.set() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { cancel?() } else { super.keyDown(with: event) }
    }
    override func rightMouseDown(with event: NSEvent) { cancel?() }
    override func mouseMoved(with event: NSEvent) {
        selectionCursor.set()
        updateHoveredTarget(at: convert(event.locationInWindow, from: nil))
    }
    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseExited(with event: NSEvent) {
        guard mode == .window || mode == .screen else { return }
        hoveredWindow = nil
        selection = nil
        needsDisplay = true
    }
    func updateHoveredTarget(at point: CGPoint) {
        if mode == .screen {
            selection = bounds.contains(point) ? bounds : nil
            needsDisplay = true
            return
        }
        guard mode == .window else { return }
        let match = bounds.contains(point) ? windowFrames.first { $0.1.contains(point) } : nil
        hoveredWindow = match?.0
        selection = match?.1.intersection(bounds)
        needsDisplay = true
    }
    override func mouseDown(with event: NSEvent) {
        if mode == .screen { return }
        if mode == .window {
            mouseMoved(with: event)
            Self.logger.info("window-mouse-down matched=\(self.hoveredWindow != nil) accepting=\(self.selected != nil)")
            return
        }
        anchor = convert(event.locationInWindow, from: nil)
    }
    override func mouseDragged(with event: NSEvent) {
        guard let anchor, mode == .area || mode == .scrolling else { return }
        let end = convert(event.locationInWindow, from: nil)
        selection = CGRect(x: min(anchor.x, end.x), y: min(anchor.y, end.y),
                           width: abs(end.x - anchor.x), height: abs(end.y - anchor.y)).intersection(bounds)
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        if mode == .screen {
            if bounds.contains(convert(event.locationInWindow, from: nil)) { selected?(nil, nil) }
        } else if mode == .window {
            updateHoveredTarget(at: convert(event.locationInWindow, from: nil))
            Self.logger.info("window-click matched=\(self.hoveredWindow != nil) candidates=\(self.windowFrames.count) accepting=\(self.selected != nil)")
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
        // The scrolling session draws its guide outside the captured area. A centered
        // selection stroke would otherwise become fixed content in every frame.
        if mode == .scrolling && !isChoosing { return }
        if let selection {
            if mode == .window || mode == .screen {
                NSColor.controlAccentColor.withAlphaComponent(0.22).setFill()
                NSBezierPath(rect: selection).fill()
            }
            NSColor.white.setStroke()
            let border = NSBezierPath(rect: selection)
            border.lineWidth = 2
            border.stroke()
        }
        let hint: String = switch mode {
        case .window: String(localized: "Click a window · Esc to cancel")
        case .screen: String(localized: "Click a screen · Esc to cancel")
        case .area, .scrolling: String(localized: "Drag to select an area · Esc to cancel")
        }
        (hint as NSString).draw(at: CGPoint(x: 24, y: bounds.height - 48), withAttributes: [
            .font: NSFont.systemFont(ofSize: 16, weight: .medium), .foregroundColor: NSColor.white,
        ])
    }
}
