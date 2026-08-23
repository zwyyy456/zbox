@preconcurrency import Carbon.HIToolbox
import Foundation

nonisolated enum HotkeyFormatter {
    static func displayName(for hotkey: Hotkey) -> String {
        let modifiers = [
            (HotkeyModifiers.control, "⌃"),
            (HotkeyModifiers.option, "⌥"),
            (HotkeyModifiers.shift, "⇧"),
            (HotkeyModifiers.command, "⌘"),
        ]
        .compactMap { hotkey.modifiers & $0.0 == 0 ? nil : $0.1 }
        .joined()

        return modifiers.isEmpty
            ? keyName(for: hotkey.keyCode)
            : "\(modifiers) \(keyName(for: hotkey.keyCode))"
    }

    private static func keyName(for keyCode: UInt32) -> String {
        if let specialName = specialKeyNames[keyCode] {
            return specialName
        }
        return translatedKeyName(for: keyCode) ?? String(localized: "Key \(keyCode)")
    }

    private static func translatedKeyName(for keyCode: UInt32) -> String? {
        guard let inputSource = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(
                inputSource,
                kTISPropertyUnicodeKeyLayoutData
              ) else { return nil }

        let data = unsafeBitCast(property, to: CFData.self)
        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var length = 0

        let status = characters.withUnsafeMutableBufferPointer { buffer in
            UCKeyTranslate(
                layout,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                buffer.count,
                &length,
                buffer.baseAddress
            )
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: Int(length)).uppercased()
    }

    private static let specialKeyNames: [UInt32: String] = [
        36: String(localized: "Return"),
        48: String(localized: "Tab"),
        49: String(localized: "Space"),
        51: String(localized: "Delete"),
        53: String(localized: "Escape"),
        71: String(localized: "Clear"),
        76: String(localized: "Enter"),
        96: "F5",
        97: "F6",
        98: "F7",
        99: "F3",
        100: "F8",
        101: "F9",
        103: "F11",
        109: "F10",
        111: "F12",
        115: String(localized: "Home"),
        116: String(localized: "Page Up"),
        117: String(localized: "Forward Delete"),
        118: "F4",
        119: String(localized: "End"),
        120: "F2",
        121: String(localized: "Page Down"),
        122: "F1",
        123: "←",
        124: "→",
        125: "↓",
        126: "↑",
    ]
}
