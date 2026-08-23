import AppKit

nonisolated enum SearchKeyboardAction: Equatable, Sendable {
    case moveSelection(Int)
    case execute
    case dismiss
}

nonisolated enum SearchKeyboardMapper {
    static func action(
        keyCode: UInt16,
        charactersIgnoringModifiers: String?,
        modifierFlags: NSEvent.ModifierFlags
    ) -> SearchKeyboardAction? {
        let modifiers = modifierFlags.intersection([.command, .control, .option, .shift])

        if modifiers.isEmpty {
            return switch keyCode {
            case 125: .moveSelection(1)
            case 126: .moveSelection(-1)
            case 36, 76: .execute
            case 53: .dismiss
            default: nil
            }
        }

        guard modifiers == .control else { return nil }
        return switch charactersIgnoringModifiers?.lowercased() {
        case "n": .moveSelection(1)
        case "p": .moveSelection(-1)
        default: nil
        }
    }
}
