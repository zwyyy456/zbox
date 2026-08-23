@preconcurrency import Carbon.HIToolbox
import Foundation

nonisolated struct Hotkey: Codable, Hashable, Sendable {
    static let defaultRootSearch = Hotkey(
        keyCode: 49,
        modifiers: UInt32(controlKey | optionKey)
    )

    let keyCode: UInt32
    let modifiers: UInt32

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = HotkeyModifiers.normalized(modifiers)
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            keyCode: try container.decode(UInt32.self, forKey: .keyCode),
            modifiers: try container.decode(UInt32.self, forKey: .modifiers)
        )
    }
}

nonisolated enum HotkeyModifiers {
    static let command = UInt32(cmdKey)
    static let shift = UInt32(shiftKey)
    static let option = UInt32(optionKey)
    static let control = UInt32(controlKey)
    static let supported = command | shift | option | control

    static func normalized(_ modifiers: UInt32) -> UInt32 {
        modifiers & supported
    }
}

nonisolated struct HotkeyAssignment: Sendable {
    let owner: String
    let hotkey: Hotkey?
}

nonisolated enum HotkeyConfigurationError: LocalizedError, Equatable {
    case conflict(String, String)
    case modifierRequired
    case modifierOnly

    var errorDescription: String? {
        switch self {
        case .conflict(let first, let second):
            "The shortcut is already used by \(first) and \(second)."
        case .modifierRequired:
            "Include Command, Control, Option, or Shift in the shortcut."
        case .modifierOnly:
            "Press a non-modifier key to complete the shortcut."
        }
    }
}

nonisolated enum HotkeyValidator {
    private static let modifierKeyCodes: Set<UInt32> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    static func validateUserShortcut(_ hotkey: Hotkey) throws {
        guard !modifierKeyCodes.contains(hotkey.keyCode) else {
            throw HotkeyConfigurationError.modifierOnly
        }
        guard hotkey.modifiers != 0 else {
            throw HotkeyConfigurationError.modifierRequired
        }
    }

    static func validate(_ assignments: [HotkeyAssignment]) throws {
        var ownersByHotkey: [Hotkey: String] = [:]

        for assignment in assignments {
            guard let hotkey = assignment.hotkey else { continue }
            if let existingOwner = ownersByHotkey[hotkey] {
                throw HotkeyConfigurationError.conflict(existingOwner, assignment.owner)
            }
            ownersByHotkey[hotkey] = assignment.owner
        }
    }
}
