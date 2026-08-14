import Foundation

nonisolated struct Hotkey: Hashable, Sendable {
    let keyCode: UInt32
    let modifiers: UInt32
}

nonisolated enum HotkeyPreset: String, CaseIterable, Identifiable, Sendable {
    case none
    case controlOptionSpace
    case optionSpace
    case controlSpace
    case commandShiftSpace
    case controlOptionLeft
    case controlOptionRight
    case controlOptionReturn
    case controlOption1
    case controlOption2
    case controlOption3

    var id: String { rawValue }

    var label: String {
        return switch self {
        case .none: "None"
        case .controlOptionSpace: "⌃⌥ Space"
        case .optionSpace: "⌥ Space"
        case .controlSpace: "⌃ Space"
        case .commandShiftSpace: "⇧⌘ Space"
        case .controlOptionLeft: "⌃⌥ ←"
        case .controlOptionRight: "⌃⌥ →"
        case .controlOptionReturn: "⌃⌥ Return"
        case .controlOption1: "⌃⌥ 1"
        case .controlOption2: "⌃⌥ 2"
        case .controlOption3: "⌃⌥ 3"
        }
    }

    var hotkey: Hotkey? {
        let command: UInt32 = 1 << 8
        let shift: UInt32 = 1 << 9
        let option: UInt32 = 1 << 11
        let control: UInt32 = 1 << 12

        return switch self {
        case .none: nil
        case .controlOptionSpace: Hotkey(keyCode: 49, modifiers: control | option)
        case .optionSpace: Hotkey(keyCode: 49, modifiers: option)
        case .controlSpace: Hotkey(keyCode: 49, modifiers: control)
        case .commandShiftSpace: Hotkey(keyCode: 49, modifiers: command | shift)
        case .controlOptionLeft: Hotkey(keyCode: 123, modifiers: control | option)
        case .controlOptionRight: Hotkey(keyCode: 124, modifiers: control | option)
        case .controlOptionReturn: Hotkey(keyCode: 36, modifiers: control | option)
        case .controlOption1: Hotkey(keyCode: 18, modifiers: control | option)
        case .controlOption2: Hotkey(keyCode: 19, modifiers: control | option)
        case .controlOption3: Hotkey(keyCode: 20, modifiers: control | option)
        }
    }

    static let rootSearchChoices: [HotkeyPreset] = [
        .controlOptionSpace,
        .optionSpace,
        .controlSpace,
        .commandShiftSpace,
    ]
}

nonisolated struct HotkeyAssignment: Sendable {
    let owner: String
    let hotkey: Hotkey?

    init(owner: String, preset: HotkeyPreset) {
        self.owner = owner
        hotkey = preset.hotkey
    }

    init(owner: String, hotkey: Hotkey?) {
        self.owner = owner
        self.hotkey = hotkey
    }
}

nonisolated enum HotkeyConfigurationError: LocalizedError, Equatable {
    case conflict(String, String)

    var errorDescription: String? {
        switch self {
        case .conflict(let first, let second):
            "The shortcut is already used by \(first) and \(second)."
        }
    }
}

nonisolated enum HotkeyValidator {
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
