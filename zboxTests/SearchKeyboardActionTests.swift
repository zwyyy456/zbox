import AppKit
import Testing
@testable import zbox

struct SearchKeyboardActionTests {
    @Test
    func mapsNavigationExecutionAndDismissalKeys() {
        #expect(action(keyCode: 125) == .moveSelection(1))
        #expect(action(keyCode: 126) == .moveSelection(-1))
        #expect(action(keyCode: 36) == .execute)
        #expect(action(keyCode: 53) == .dismiss)
        #expect(action(keyCode: 45, characters: "n", modifiers: .control) == .moveSelection(1))
        #expect(action(keyCode: 35, characters: "p", modifiers: .control) == .moveSelection(-1))
    }

    @Test
    func ignoresModifiedControlBindingsAndPlainLetters() {
        #expect(action(keyCode: 45, characters: "n") == nil)
        #expect(action(keyCode: 45, characters: "n", modifiers: [.control, .shift]) == nil)
        #expect(action(keyCode: 45, characters: "n", modifiers: .command) == nil)
    }

    private func action(
        keyCode: UInt16,
        characters: String? = nil,
        modifiers: NSEvent.ModifierFlags = []
    ) -> SearchKeyboardAction? {
        SearchKeyboardMapper.action(
            keyCode: keyCode,
            charactersIgnoringModifiers: characters,
            modifierFlags: modifiers
        )
    }
}
