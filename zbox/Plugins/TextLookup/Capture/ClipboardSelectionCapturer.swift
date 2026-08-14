import AppKit
import CoreGraphics

@MainActor
final class ClipboardSelectionCapturer {
    private struct Snapshot {
        let items: [[NSPasteboard.PasteboardType: Data]]
    }

    func capture(_ request: TextCaptureRequest) async throws -> TextLookupCapture {
        let pasteboard = NSPasteboard.general
        let snapshot = snapshot(of: pasteboard)
        let initialChangeCount = pasteboard.changeCount
        postCopyShortcut()

        var copiedText: String?
        var copiedChangeCount: Int?
        for _ in 0..<10 {
            await waitForPasteboardUpdate()
            guard pasteboard.changeCount != initialChangeCount else { continue }
            copiedChangeCount = pasteboard.changeCount
            copiedText = pasteboard.string(forType: .string)
            break
        }

        if let copiedChangeCount, pasteboard.changeCount == copiedChangeCount {
            restore(snapshot, to: pasteboard)
        }
        try Task.checkCancellation()
        guard let copiedText else { throw TextCaptureError.clipboardFallbackFailed }
        let cleaned = try TextLookupTextProcessor.cleanSelection(copiedText)
        let anchorRect = request.fallbackAnchorPoint.map {
            CGRect(x: $0.x, y: $0.y, width: 1, height: 1)
        }

        return TextLookupCapture(
            id: request.id,
            term: cleaned.term,
            sentence: nil,
            sourceURL: nil,
            anchorRect: anchorRect,
            sourceApplicationBundleIdentifier: request.targetApplicationBundleIdentifier
        )
    }

    private func snapshot(of pasteboard: NSPasteboard) -> Snapshot {
        let items = pasteboard.pasteboardItems?.map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        } ?? []
        return Snapshot(items: items)
    }

    private func restore(_ snapshot: Snapshot, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let items = snapshot.items.map { values in
            let item = NSPasteboardItem()
            for (type, data) in values {
                item.setData(data, forType: type)
            }
            return item
        }
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }

    private func postCopyShortcut() {
        let source = CGEventSource(stateID: .hidSystemState)
        let commandFlag = CGEventFlags.maskCommand
        let keyCode: CGKeyCode = 8
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyDown?.flags = commandFlag
        keyUp?.flags = commandFlag
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    private func waitForPasteboardUpdate() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                continuation.resume()
            }
        }
    }
}
