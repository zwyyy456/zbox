import AppKit
import SwiftUI

struct ShortcutRecorder: NSViewRepresentable {
    let hotkey: Hotkey?
    let allowsClearing: Bool
    let accessibilityLabel: String
    let onChange: (Hotkey?) -> Void
    let onInvalid: (String) -> Void
    let onRecordingChanged: (Bool) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        update(button)
        return button
    }

    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        update(button)
    }

    static func dismantleNSView(_ button: ShortcutRecorderButton, coordinator: Void) {
        button.cancelRecording()
    }

    private func update(_ button: ShortcutRecorderButton) {
        button.hotkey = hotkey
        button.allowsClearing = allowsClearing
        button.onChange = onChange
        button.onInvalid = onInvalid
        button.onRecordingChanged = onRecordingChanged
        button.setAccessibilityLabel(accessibilityLabel)
        button.refreshTitle()
    }
}

@MainActor
final class ShortcutRecorderButton: NSButton {
    var hotkey: Hotkey?
    var allowsClearing = false
    var onChange: ((Hotkey?) -> Void)?
    var onInvalid: ((String) -> Void)?
    var onRecordingChanged: ((Bool) -> Void)?

    private var isRecording = false
    private var sawModifier = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        controlSize = .regular
        setButtonType(.momentaryPushIn)
        focusRingType = .default
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        beginRecording()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording, !event.isARepeat else {
            super.keyDown(with: event)
            return
        }

        let modifiers = carbonModifiers(from: event.modifierFlags)
        switch (event.keyCode, modifiers) {
        case (53, _):
            cancelRecording()
        case (51, 0), (117, 0):
            guard allowsClearing else {
                NSSound.beep()
                return
            }
            onChange?(nil)
            finishRecording()
        default:
            let hotkey = Hotkey(keyCode: UInt32(event.keyCode), modifiers: modifiers)
            do {
                try HotkeyValidator.validateUserShortcut(hotkey)
                onChange?(hotkey)
                finishRecording()
            } catch {
                onInvalid?(error.localizedDescription)
                NSSound.beep()
            }
        }
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else {
            super.flagsChanged(with: event)
            return
        }

        if carbonModifiers(from: event.modifierFlags) != 0 {
            sawModifier = true
            title = "Press another key…"
        } else if sawModifier {
            sawModifier = false
            onInvalid?(HotkeyConfigurationError.modifierOnly.localizedDescription)
        }
    }

    override func resignFirstResponder() -> Bool {
        let didResign = super.resignFirstResponder()
        if didResign, isRecording {
            endRecording()
        }
        return didResign
    }

    func cancelRecording() {
        guard isRecording else { return }
        finishRecording()
    }

    func refreshTitle() {
        guard !isRecording else { return }
        title = hotkey.map(HotkeyFormatter.displayName(for:)) ?? "Not Set"
        setAccessibilityValue(title)
    }

    private func beginRecording() {
        guard !isRecording, window?.makeFirstResponder(self) == true else { return }
        isRecording = true
        sawModifier = false
        title = "Type Shortcut…"
        onRecordingChanged?(true)
    }

    private func finishRecording() {
        endRecording()
        window?.makeFirstResponder(nil)
    }

    private func endRecording() {
        guard isRecording else { return }
        isRecording = false
        sawModifier = false
        refreshTitle()
        onRecordingChanged?(false)
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        let flags = flags.intersection(.deviceIndependentFlagsMask)
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= HotkeyModifiers.command }
        if flags.contains(.shift) { modifiers |= HotkeyModifiers.shift }
        if flags.contains(.option) { modifiers |= HotkeyModifiers.option }
        if flags.contains(.control) { modifiers |= HotkeyModifiers.control }
        return modifiers
    }
}
