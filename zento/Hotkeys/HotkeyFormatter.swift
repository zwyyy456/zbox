@preconcurrency import Carbon.HIToolbox
import Foundation
import SwiftUI

nonisolated enum HotkeyFormatter {
    static func keyboardShortcut(for hotkey: Hotkey) -> KeyboardShortcut? {
        let key: KeyEquivalent
        if let specialKey = menuSpecialKeys[hotkey.keyCode] {
            key = specialKey
        } else if let index = functionKeyCodes.firstIndex(of: hotkey.keyCode) {
            // AppKit represents F1–F20 using consecutive function-key Unicode scalars.
            key = KeyEquivalent(Character(UnicodeScalar(0xF704 + index)!))
        } else if let name = translatedKeyName(for: hotkey.keyCode)?.lowercased(),
                  name.count == 1, let character = name.first {
            key = KeyEquivalent(character)
        } else {
            return nil
        }

        var modifiers: SwiftUI.EventModifiers = []
        if hotkey.modifiers & HotkeyModifiers.control != 0 { modifiers.insert(.control) }
        if hotkey.modifiers & HotkeyModifiers.option != 0 { modifiers.insert(.option) }
        if hotkey.modifiers & HotkeyModifiers.shift != 0 { modifiers.insert(.shift) }
        if hotkey.modifiers & HotkeyModifiers.command != 0 { modifiers.insert(.command) }
        return KeyboardShortcut(key, modifiers: modifiers)
    }

    private static let menuSpecialKeys: [UInt32: KeyEquivalent] = [
        36: .return, 48: .tab, 49: .space, 51: .delete, 53: .escape,
        71: .clear, 76: KeyEquivalent("\u{0003}"),
        115: .home, 116: .pageUp, 117: .deleteForward, 119: .end, 121: .pageDown,
        123: .leftArrow, 124: .rightArrow, 125: .downArrow, 126: .upArrow,
    ]

    private static let functionKeyCodes: [UInt32] = [
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109,
        103, 111, 105, 107, 113, 106, 64, 79, 80, 90,
    ]

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
