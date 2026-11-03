import AppKit

@MainActor
final class ClipboardHistoryPanel: TransientPanel {
    var navigate: ((Int) -> Void)?
    var paste: (() -> Void)?
    var pasteItem: ((Int) -> Void)?
    var copy: (() -> Void)?
    var dismiss: (() -> Void)?


    func present() {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let visibleFrame = screen?.visibleFrame {
            setFrameOrigin(NSPoint(x: visibleFrame.midX - frame.width / 2,
                                   y: visibleFrame.midY - frame.height / 2))
        }
        presentTransient()
    }

    override func close() {
        dismiss?()
        super.close()
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, attachedSheet == nil {
            // Let the input method finish composing before handling panel shortcuts.
            if (firstResponder as? NSTextView)?.hasMarkedText() == true {
                super.sendEvent(event)
                return
            }
            let modifiers = event.modifierFlags.intersection([.command, .control, .shift, .option])
            if modifiers == .command, let characters = event.charactersIgnoringModifiers,
               let number = Int(characters), (1...9).contains(number) {
                pasteItem?(number - 1)
                return
            }
            if [36, 76].contains(event.keyCode), modifiers == .command {
                copy?()
                return
            }
            if let action = SearchKeyboardMapper.action(keyCode: event.keyCode,
                charactersIgnoringModifiers: event.charactersIgnoringModifiers, modifierFlags: event.modifierFlags) {
                switch action {
                case .moveSelection(let offset): navigate?(offset)
                case .execute: paste?()
                case .dismiss: dismiss?()
                }
                return
            }
        }
        super.sendEvent(event)
    }
}
