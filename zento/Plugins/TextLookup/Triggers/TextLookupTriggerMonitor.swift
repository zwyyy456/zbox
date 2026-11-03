import AppKit

@MainActor
final class TextLookupTriggerMonitor {
    var onMouseDown: (() -> Void)?
    var onMouseUp: ((CGPoint) -> Void)?
    var onDoubleOption: (() -> Void)?

    private var eventMonitor: Any?
    private var doubleTapDetector = ModifierDoubleTapDetector()

    func start() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [
                .leftMouseDown,
                .rightMouseDown,
                .otherMouseDown,
                .leftMouseUp,
                .flagsChanged,
                .keyDown,
            ]
        ) { [weak self] event in
            self?.handle(event)
        }
    }

    func stop() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        doubleTapDetector.reset()
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            onMouseDown?()
        case .leftMouseUp:
            onMouseUp?(NSEvent.mouseLocation)
        case .keyDown:
            doubleTapDetector.ordinaryKeyPressed()
        case .flagsChanged:
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let hasOtherModifiers = !modifiers.subtracting(.option).isEmpty
            if doubleTapDetector.flagsChanged(
                keyCode: event.keyCode,
                optionIsDown: modifiers.contains(.option),
                hasOtherModifiers: hasOtherModifiers,
                timestamp: event.timestamp
            ) {
                onDoubleOption?()
            }
        default:
            break
        }
    }
}
