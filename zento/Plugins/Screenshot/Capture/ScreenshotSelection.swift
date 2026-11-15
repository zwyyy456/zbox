import AppKit
import ScreenCaptureKit
import OSLog

struct ScreenshotSelectionTarget {
    let window: SCWindow
    let hitFrame: CGRect
    let captureFrame: CGRect
}

@MainActor
final class ScreenshotSelection: NSObject, NSWindowDelegate {
    private var panels: [NSPanel] = []
    private weak var pendingKeyPanel: NSPanel?

    func show(mode: ScreenshotMode, windows: [SCWindow], snapshots: [CGDirectDisplayID: CGImage] = [:],
              frozenWindowTargets: [ScreenshotSelectionTarget]? = nil,
              selected: @escaping (NSScreen, CGRect?, SCWindow?) -> Void, cancelled: @escaping () -> Void) {
        close()
        let screens = NSScreen.screens
        let primaryHeight = screens.first?.frame.maxY ?? 0
        let mouseLocation = NSEvent.mouseLocation
        for screen in screens {
            let panel = ScreenshotSelectionPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            let snapshot = ScreenshotCapture.displayID(for: screen).flatMap { snapshots[$0] }
            panel.isOpaque = snapshot != nil
            panel.backgroundColor = snapshot == nil ? .clear : .black
            panel.delegate = self
            panel.animationBehavior = .none
            panel.hasShadow = false
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.acceptsMouseMovedEvents = true
            panel.isReleasedWhenClosed = false
            let view = ScreenshotSelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.mode = mode
            view.snapshot = snapshot
            view.pixelScale = screen.backingScaleFactor
            view.windowFrames = {
                let targets = frozenWindowTargets ?? Self.currentWindowFrames(windows).map {
                    ScreenshotSelectionTarget(window: $0.0, hitFrame: $0.1, captureFrame: $0.1)
                }
                return targets.map {
                    ScreenshotSelectionTarget(window: $0.window,
                        hitFrame: ScreenshotGeometry.screenRect($0.hitFrame, primaryHeight: primaryHeight)
                            .offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY),
                        captureFrame: ScreenshotGeometry.screenRect($0.captureFrame, primaryHeight: primaryHeight)
                            .offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY))
                }
            }
            view.cancel = cancelled
            view.selected = { rect, window in
                selected(screen, rect?.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY), window)
            }
            panel.contentView = view
            panel.makeFirstResponder(view)
            view.updateHoveredTarget(at: view.convert(panel.convertPoint(fromScreen: mouseLocation), from: nil))
            // Initialize the hidden window's backing store, then explicitly draw the view into it.
            // Neither call alone renders the first frame before focus can dismiss a source menu.
            panel.display()
            view.display()
            panels.append(panel)
        }
        pendingKeyPanel = panels.first(where: { $0.frame.contains(mouseLocation) })
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            for panel in panels {
                panel.orderFrontRegardless()
                panel.displayIfNeeded()
            }
        }
    }

    func windowDidChangeOcclusionState(_ notification: Notification) {
        guard let panel = notification.object as? NSPanel,
              panel === pendingKeyPanel, panel.occlusionState.contains(.visible) else { return }
        // Drawing a backing store is not presentation. Transfer focus only after Window Server
        // reports this panel visible, so closing a source menu happens behind the frozen image.
        pendingKeyPanel = nil
        panel.makeKey()
    }

    static func freezeWindowTargets(_ windows: [SCWindow]) -> [ScreenshotSelectionTarget] {
        let frames = currentWindowFrames(windows)
        let shared = Dictionary(uniqueKeysWithValues: windows.map { ($0.windowID, $0) })
        let surfaces = frames.map {
            ScreenshotWindowTargets.Surface(id: $0.0.windowID, ownerPID: $0.0.owningApplication?.processID,
                                            layer: $0.0.windowLayer, frame: $0.1)
        }
        return ScreenshotWindowTargets.grouped(surfaces).map {
            ScreenshotSelectionTarget(window: shared[$0.windowID]!, hitFrame: $0.hitFrame, captureFrame: $0.captureFrame)
        }
    }

    private static func currentWindowFrames(_ windows: [SCWindow]) -> [(SCWindow, CGRect)] {
        let info = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        let shared = Dictionary(uniqueKeysWithValues: windows.map { ($0.windowID, $0) })
        return ScreenshotGeometry.selectableWindowFrames(info).compactMap { id, frame in
            guard let window = shared[id] else { return nil }
            return (window, frame)
        }
    }

    func finishChoosing() {
        for panel in panels {
            (panel.contentView as? ScreenshotSelectionView)?.finishChoosing()
            panel.ignoresMouseEvents = true
        }
    }

    func close() {
        pendingKeyPanel = nil
        for panel in panels { panel.delegate = nil; panel.orderOut(nil); panel.close() }
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
    var snapshot: CGImage?
    var pixelScale: CGFloat = 1
    private var pointer: CGPoint?
    private var showsPrecision = false
    var mode = ScreenshotMode.area
    var windowFrames: () -> [ScreenshotSelectionTarget] = { [] }
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

    override var isOpaque: Bool { snapshot != nil }
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
    override func flagsChanged(with event: NSEvent) {
        showsPrecision = event.modifierFlags.contains(.option)
        needsDisplay = true
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { cancel?() } else { super.keyDown(with: event) }
    }
    override func rightMouseDown(with event: NSEvent) { cancel?() }
    override func mouseMoved(with event: NSEvent) {
        selectionCursor.set()
        pointer = convert(event.locationInWindow, from: nil)
        showsPrecision = event.modifierFlags.contains(.option)
        updateHoveredTarget(at: pointer!)
        needsDisplay = true
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
        let match = bounds.contains(point) ? windowFrames().first { $0.hitFrame.contains(point) } : nil
        hoveredWindow = match?.window
        selection = match?.captureFrame.intersection(bounds)
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
        pointer = end
        showsPrecision = event.modifierFlags.contains(.option)
        selection = CGRect(x: min(anchor.x, end.x), y: min(anchor.y, end.y),
                           width: abs(end.x - anchor.x), height: abs(end.y - anchor.y)).intersection(bounds)
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        if mode == .screen {
            if bounds.contains(convert(event.locationInWindow, from: nil)) { selected?(nil, nil) }
        } else if mode == .window {
            updateHoveredTarget(at: convert(event.locationInWindow, from: nil))
            Self.logger.info("window-click matched=\(self.hoveredWindow != nil) accepting=\(self.selected != nil)")
            if let hoveredWindow { selected?(snapshot == nil ? nil : selection, hoveredWindow) }
        } else {
            mouseDragged(with: event)
            if let selection, selection.width >= 1, selection.height >= 1 { selected?(selection, nil) }
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        if let snapshot {
            NSGraphicsContext.current?.cgContext.draw(snapshot, in: bounds)
        }
        let shade = NSBezierPath(rect: bounds)
        if let selection { shade.appendRect(selection) }
        shade.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.22).setFill()
        shade.fill()
        if !isChoosing { return }
        if let selection {
            if mode == .window || mode == .screen {
                NSColor.controlAccentColor.withAlphaComponent(0.07).setFill()
                NSBezierPath(rect: selection).fill()
            }
            let border = NSBezierPath(rect: selection)
            NSColor.black.withAlphaComponent(0.7).setStroke()
            border.lineWidth = 2
            border.stroke()
            NSColor.white.setStroke()
            border.lineWidth = 1
            border.stroke()
            let pixels: CGSize
            if let snapshot {
                pixels = ScreenshotGeometry.snapshotPixelRect(selection, in: bounds,
                    pixels: CGSize(width: snapshot.width, height: snapshot.height)).size
            } else {
                pixels = CGSize(width: selection.width * pixelScale, height: selection.height * pixelScale)
            }
            let dimensions = String(localized: "\(Int(pixels.width.rounded())) × \(Int(pixels.height.rounded())) px")
            let label = hoveredWindow?.owningApplication.map { "\($0.applicationName) · \(dimensions)" } ?? dimensions
            drawLabel(label,
                      near: CGPoint(x: selection.minX, y: selection.minY - 30))
        }
        if showsPrecision, let snapshot, let pointer {
            drawPrecision(snapshot: snapshot, at: pointer)
        }
        let hint: String = switch mode {
        case .window: String(localized: "Click a window · Esc to cancel")
        case .screen: String(localized: "Click a screen · Esc to cancel")
        case .area where snapshot != nil: String(localized: "Drag to select · Option for precision · Esc to cancel")
        case .area, .scrolling: String(localized: "Drag to select an area · Esc to cancel")
        }
        if anchor == nil {
            drawLabel(hint, near: CGPoint(x: 20, y: bounds.height - 44))
        }
    }

    private func drawLabel(_ text: String, near point: CGPoint) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let box = CGRect(x: min(max(8, point.x), bounds.width - size.width - 24),
                         y: min(max(8, point.y), bounds.height - size.height - 20),
                         width: size.width + 16, height: size.height + 10)
        NSColor.black.withAlphaComponent(0.8).setFill()
        NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6).fill()
        (text as NSString).draw(at: CGPoint(x: box.minX + 8, y: box.minY + 5), withAttributes: attributes)
    }

    private func drawPrecision(snapshot: CGImage, at point: CGPoint) {
        let guides = NSBezierPath()
        guides.move(to: CGPoint(x: point.x, y: 0)); guides.line(to: CGPoint(x: point.x, y: bounds.height))
        guides.move(to: CGPoint(x: 0, y: point.y)); guides.line(to: CGPoint(x: bounds.width, y: point.y))
        NSColor.white.withAlphaComponent(0.5).setStroke()
        guides.lineWidth = 0.5
        guides.stroke()
        let pixel = CGPoint(x: point.x / bounds.width * CGFloat(snapshot.width),
                            y: (bounds.height - point.y) / bounds.height * CGFloat(snapshot.height))
        let sample = CGRect(x: min(max(0, pixel.x - 10), CGFloat(snapshot.width) - 20),
                            y: min(max(0, pixel.y - 10), CGFloat(snapshot.height) - 20), width: 20, height: 20)
        guard let image = snapshot.cropping(to: sample), let context = NSGraphicsContext.current?.cgContext else { return }
        let box = CGRect(x: point.x + 120 < bounds.width ? point.x + 20 : point.x - 120,
                         y: point.y > 120 ? point.y - 120 : point.y + 20, width: 100, height: 100)
        context.saveGState()
        context.interpolationQuality = .none
        context.draw(image, in: box)
        context.restoreGState()
        NSColor.white.setStroke()
        let border = NSBezierPath(rect: box); border.lineWidth = 1; border.stroke()
        let cross = NSBezierPath()
        let cursorX = box.minX + (pixel.x - sample.minX) * box.width / sample.width
        let cursorY = box.maxY - (pixel.y - sample.minY) * box.height / sample.height
        cross.move(to: CGPoint(x: cursorX, y: box.minY)); cross.line(to: CGPoint(x: cursorX, y: box.maxY))
        cross.move(to: CGPoint(x: box.minX, y: cursorY)); cross.line(to: CGPoint(x: box.maxX, y: cursorY))
        NSColor.black.withAlphaComponent(0.7).setStroke()
        cross.lineWidth = 1
        cross.stroke()
    }
}
