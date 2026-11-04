import AppKit
import SwiftUI

struct ShortcutRecorder: NSViewRepresentable {
    enum Presentation {
        case button
        case table
    }

    @Environment(\.controlActiveState) private var controlActiveState
    let hotkey: Hotkey?
    let allowsClearing: Bool
    let accessibilityLabel: String
    let onChange: (Hotkey?) -> Void
    let onInvalid: (String) -> Void
    let onRecordingChanged: (Bool) -> Void
    var modifierOnly: UInt32? = nil
    var onModifierOnly: ((UInt32) -> Void)? = nil
    var presentation: Presentation = .button
    var isSelected = false

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
        button.presentation = presentation
        button.isEmphasized = isSelected && controlActiveState != .inactive
        button.isBordered = presentation == .button
        button.focusRingType = presentation == .button ? .default : .none
        button.hotkey = hotkey
        button.modifierOnly = modifierOnly
        button.onModifierOnly = onModifierOnly
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
    var presentation: ShortcutRecorder.Presentation = .button
    var isEmphasized = false
    var hotkey: Hotkey?
    var allowsClearing = false
    var modifierOnly: UInt32?
    var onModifierOnly: ((UInt32) -> Void)?
    private var recordedModifiers: UInt32 = 0
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

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if presentation == .table, isRecording {
            let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 5, yRadius: 5)
            (isEmphasized ? NSColor.alternateSelectedControlTextColor : NSColor.controlAccentColor).setStroke()
            outline.lineWidth = 1.5
            outline.stroke()
        }
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
            recordedModifiers |= carbonModifiers(from: event.modifierFlags)
            title = onModifierOnly == nil ? String(localized: "Press another key…")
                : String(localized: "Release modifiers, or press another key…")
            refreshTitle()
        } else if sawModifier {
            sawModifier = false
            if let onModifierOnly {
                onModifierOnly(recordedModifiers)
                finishRecording()
            } else {
                onInvalid?(HotkeyConfigurationError.modifierOnly.localizedDescription)
            }
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
        needsDisplay = true
        if isRecording {
            applyTitle(title)
            return
        }
        let modifierText = modifierOnly.map { value in
            [(HotkeyModifiers.control, "⌃"), (HotkeyModifiers.option, "⌥"),
             (HotkeyModifiers.shift, "⇧"), (HotkeyModifiers.command, "⌘")]
                .filter { value & $0.0 != 0 }.map(\.1).joined()
        }
        let text = hotkey.map(HotkeyFormatter.displayName(for:)) ?? modifierText ?? (presentation == .table ? String(localized: "Record…") : String(localized: "Record Shortcut"))
        applyTitle(text)
        setAccessibilityValue(hotkey == nil && modifierOnly == nil ? String(localized: "Not Set") : text)
    }

    private func applyTitle(_ text: String) {
        let color: NSColor
        if presentation == .table {
            color = isEmphasized ? .alternateSelectedControlTextColor
                : (hotkey == nil && modifierOnly == nil && !isRecording ? .linkColor : .labelColor)
        } else {
            color = hotkey == nil && modifierOnly == nil && !isRecording ? .tertiaryLabelColor : .labelColor
        }
        attributedTitle = NSAttributedString(string: text, attributes: [
            .foregroundColor: color,
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
        ])
    }

    private func beginRecording() {
        guard !isRecording, window?.makeFirstResponder(self) == true else { return }
        isRecording = true
        sawModifier = false
        recordedModifiers = 0
        title = String(localized: "Type Shortcut…")
        refreshTitle()
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
