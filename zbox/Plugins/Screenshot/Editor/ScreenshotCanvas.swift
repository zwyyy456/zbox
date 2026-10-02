import AppKit
import SwiftUI

struct ScreenshotCanvas: NSViewRepresentable {
    let document: ScreenshotDocument
    func makeNSView(context: Context) -> ScreenshotCanvasView { ScreenshotCanvasView() }
    func updateNSView(_ view: ScreenshotCanvasView, context: Context) {
        view.document = document
        // Reading edit here makes SwiftUI invalidate the canvas after undo/redo.
        view.edit = document.edit
        view.needsDisplay = true
    }
}

final class ScreenshotCanvasView: NSView {
    var document: ScreenshotDocument?
    var edit: ScreenshotEdit?
    private var pending: ScreenshotMark?
    private var anchor: CGPoint?
    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    private func imagePoint(_ event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        guard let edit else { return point }
        return CGPoint(x: edit.crop.minX + min(max(point.x, 0), bounds.width) * edit.crop.width / bounds.width,
                       y: edit.crop.minY + min(max(point.y, 0), bounds.height) * edit.crop.height / bounds.height)
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        anchor = imagePoint(event)
    }
    override func mouseDragged(with event: NSEvent) {
        guard let document, let anchor else { return }
        pending = ScreenshotMark(tool: document.tool, start: anchor, end: imagePoint(event), text: document.text)
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        guard let document, let anchor else { return }
        document.commit(ScreenshotMark(tool: document.tool, start: anchor, end: imagePoint(event), text: document.text))
        self.anchor = nil
        pending = nil
        needsDisplay = true
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { pending = nil; anchor = nil; needsDisplay = true }
        else { super.keyDown(with: event) }
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let document, var edit, let context = NSGraphicsContext.current?.cgContext else { return }
        if let pending, pending.tool != .crop { edit.marks.append(pending) }
        context.saveGState()
        context.scaleBy(x: bounds.width / edit.crop.width, y: bounds.height / edit.crop.height)
        ScreenshotRenderer.draw(image: document.image, edit: edit, in: context)
        if let pending, pending.tool == .crop {
            context.setStrokeColor(NSColor.controlAccentColor.cgColor)
            context.setLineWidth(2 / document.zoom)
            context.setLineDash(phase: 0, lengths: [6 / document.zoom, 4 / document.zoom])
            context.stroke(pending.rect.offsetBy(dx: -edit.crop.minX, dy: -edit.crop.minY))
        }
        context.restoreGState()
    }
}
