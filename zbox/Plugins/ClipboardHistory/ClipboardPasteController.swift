import AppKit
import CoreGraphics

@MainActor
enum ClipboardPasteController {
    static func activate(_ target: NSRunningApplication) async throws {
        guard !target.isTerminated, target.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            throw ClipboardHistoryError.targetUnavailable
        }
        let previousPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard target.activate() else { throw ClipboardHistoryError.targetUnavailable }
        for _ in 0..<20 {
            try Task.checkCancellation()
            let currentPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            if currentPID == target.processIdentifier, !target.isTerminated { return }
            guard currentPID == previousPID || currentPID == ProcessInfo.processInfo.processIdentifier else {
                throw ClipboardHistoryError.targetUnavailable
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw ClipboardHistoryError.targetUnavailable
    }

    static func paste(into target: NSRunningApplication) throws {
        guard !target.isTerminated,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier else {
            throw ClipboardHistoryError.targetUnavailable
        }
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false) else {
            throw ClipboardHistoryError.targetUnavailable
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}

@MainActor
final class ClipboardHistoryPanel: NSPanel {
    var navigate: ((Int) -> Void)?
    var paste: (() -> Void)?
    var copy: (() -> Void)?
    var dismiss: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

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
