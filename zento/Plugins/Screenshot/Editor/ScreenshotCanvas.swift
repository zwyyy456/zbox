import AppKit
import SwiftUI

struct ScreenshotCanvas: NSViewRepresentable {
    let document: ScreenshotDocument
    func makeNSView(context: Context) -> ScreenshotCanvasView {
        let view = ScreenshotCanvasView()
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.group)
        view.setAccessibilityLabel(String(localized: "Screenshot"))
        return view
    }
    func updateNSView(_ view: ScreenshotCanvasView, context: Context) {
        view.document = document
        view.isEnabled = context.environment.isEnabled
        // Reading edit here makes SwiftUI invalidate the canvas after undo/redo.
        view.tool = document.tool
        view.edit = document.edit
        view.needsDisplay = true
    }
}

final class ScreenshotCanvasView: NSView, NSTextFieldDelegate {
    var isEnabled = true
    var document: ScreenshotDocument? {
        didSet { if document !== oldValue { finishText(cancelled: true) } }
    }
    var edit: ScreenshotEdit?
    var tool: ScreenshotTool = .arrow {
        didSet { window?.invalidateCursorRects(for: self) }
    }
    private var textField: NSTextField?
    private var textMark: ScreenshotMark?
    private var textIndex: Int?
    private var pending: ScreenshotMark?
    private var anchor: CGPoint?
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: tool == .text ? .iBeam : .crosshair) }

    private func imagePoint(_ event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        guard let edit else { return point }
        return CGPoint(x: edit.crop.minX + min(max(point.x, 0), bounds.width) * edit.crop.width / bounds.width,
                       y: edit.crop.minY + min(max(point.y, 0), bounds.height) * edit.crop.height / bounds.height)
    }
    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        window?.makeFirstResponder(self)
        guard let document else { return }
        let point = imagePoint(event)
        if document.tool == .text {
            let index = document.edit.marks.lastIndex { mark in
                guard mark.tool == .text else { return false }
                let size = (mark.text as NSString).size(withAttributes: [.font: NSFont(name: "Helvetica", size: mark.textSize)!])
                return CGRect(x: mark.start.x, y: mark.start.y - mark.textSize * 0.25,
                              width: max(size.width, 16 / document.zoom), height: mark.textSize * 1.3).contains(point)
            }
            beginText(at: point, index: index)
            return
        }
        anchor = point
    }
    override func mouseDragged(with event: NSEvent) {
        guard isEnabled, let document, let anchor else { return }
        pending = ScreenshotMark(tool: document.tool, start: anchor, end: imagePoint(event), text: "")
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        guard isEnabled, let document, let anchor else { return }
        document.commit(ScreenshotMark(tool: document.tool, start: anchor, end: imagePoint(event), text: ""))
        self.anchor = nil
        pending = nil
        needsDisplay = true
    }
    private func beginText(at point: CGPoint, index: Int?) {
        guard let document else { return }
        textIndex = index
        let mark = index.map { document.edit.marks[$0] }
            ?? ScreenshotMark(tool: .text, start: point, end: point, text: "", textSize: 18 / document.zoom)
        textMark = mark
        let x = (mark.start.x - document.edit.crop.minX) * document.zoom
        let y = (mark.start.y - document.edit.crop.minY) * document.zoom
        let field = NSTextField(string: mark.text)
        field.font = NSFont(name: "Helvetica", size: mark.textSize * document.zoom)
        field.textColor = .systemRed
        field.backgroundColor = .textBackgroundColor
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.placeholderString = String(localized: "Text")
        field.delegate = self
        let height = max(26, mark.textSize * document.zoom + 8)
        field.frame = CGRect(x: min(x, max(0, bounds.width - 100)),
                             y: min(max(0, y - 6), max(0, bounds.height - height)),
                             width: min(max(100, bounds.width - x), 320), height: height)
        textField = field
        addSubview(field)
        field.selectText(nil)
        needsDisplay = true
    }

    func controlTextDidEndEditing(_ notification: Notification) { finishText(cancelled: false) }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            finishText(cancelled: true)
        } else if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            finishText(cancelled: false)
        } else { return false }
        window?.makeFirstResponder(self)
        return true
    }

    private func finishText(cancelled: Bool) {
        guard let field = textField, let mark = textMark else { return }
        let index = textIndex
        textField = nil
        textMark = nil
        textIndex = nil
        field.delegate = nil
        if !cancelled {
            let updated = ScreenshotMark(tool: .text, start: mark.start, end: mark.end,
                                         text: field.stringValue, textSize: mark.textSize)
            if let index { document?.replaceText(at: index, with: updated) }
            else { document?.commit(updated) }
        }
        field.removeFromSuperview()
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { pending = nil; anchor = nil; needsDisplay = true }
        else { super.keyDown(with: event) }
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let document, var edit, let context = NSGraphicsContext.current?.cgContext else { return }
        if let textIndex { edit.marks.remove(at: textIndex) }
        if let pending, pending.tool != .crop { edit.marks.append(pending) }
        context.saveGState()
        context.scaleBy(x: bounds.width / edit.crop.width, y: bounds.height / edit.crop.height)
        do { try ScreenshotRenderer.draw(image: document.image, edit: edit, in: context) }
        catch {
            context.restoreGState()
            NSColor.windowBackgroundColor.setFill()
            bounds.fill()
            (ScreenshotError.exportFailed.localizedDescription as NSString).draw(at: CGPoint(x: 12, y: 12),
                withAttributes: [.foregroundColor: NSColor.labelColor, .font: NSFont.systemFont(ofSize: 13)])
            return
        }
        if let pending, pending.tool == .crop {
            context.setStrokeColor(NSColor.controlAccentColor.cgColor)
            context.setLineWidth(2 / document.zoom)
            context.setLineDash(phase: 0, lengths: [6 / document.zoom, 4 / document.zoom])
            context.stroke(pending.rect.offsetBy(dx: -edit.crop.minX, dy: -edit.crop.minY))
        }
        context.restoreGState()
    }
}
