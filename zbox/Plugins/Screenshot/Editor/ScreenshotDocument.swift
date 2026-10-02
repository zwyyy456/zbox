import CoreGraphics
import Foundation
import Observation

nonisolated enum ScreenshotTool: String, CaseIterable, Identifiable {
    case crop, arrow, rectangle, text, redact
    var id: String { rawValue }
    var title: String {
        switch self {
        case .crop: String(localized: "Crop")
        case .arrow: String(localized: "Arrow")
        case .rectangle: String(localized: "Rectangle")
        case .text: String(localized: "Text")
        case .redact: String(localized: "Cover")
        }
    }
}

nonisolated struct ScreenshotMark: Sendable {
    let tool: ScreenshotTool
    let start: CGPoint
    let end: CGPoint
    let text: String
    var rect: CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y))
    }
}

nonisolated struct ScreenshotEdit: Sendable {
    var crop: CGRect
    var marks: [ScreenshotMark] = []
}

@MainActor
@Observable
final class ScreenshotDocument {
    let image: CGImage
    private(set) var edit: ScreenshotEdit
    private var undoStack: [ScreenshotEdit] = []
    private var redoStack: [ScreenshotEdit] = []
    var tool = ScreenshotTool.arrow
    var text = ""
    var zoom = 0.5
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    init(image: CGImage) {
        self.image = image
        edit = ScreenshotEdit(crop: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        zoom = min(1, 780 / Double(image.width), 460 / Double(image.height))
    }

    func commit(_ mark: ScreenshotMark) {
        if mark.tool == .text {
            guard !mark.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        } else {
            guard hypot(mark.end.x - mark.start.x, mark.end.y - mark.start.y) >= 1 else { return }
        }
        var next = edit
        if mark.tool == .crop {
            let rect = mark.rect.intersection(edit.crop).integral.intersection(edit.crop)
            guard rect.width >= 1, rect.height >= 1 else { return }
            next.crop = rect
        } else { next.marks.append(mark) }
        undoStack.append(edit)
        redoStack.removeAll()
        edit = next
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(edit)
        edit = previous
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(edit)
        edit = next
    }
}
