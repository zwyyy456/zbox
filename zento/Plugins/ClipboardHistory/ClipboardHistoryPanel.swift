import AppKit

@MainActor
final class ClipboardHistoryPanel: NSPanel {
    var navigate: ((Int) -> Void)?
    var paste: (() -> Void)?
    var copy: (() -> Void)?
    var dismiss: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func close() {
        dismiss?()
        super.close()
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            let modifiers = event.modifierFlags.intersection([.command, .control, .shift, .option])
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
