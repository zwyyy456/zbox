import AppKit
import Testing
@testable import zento

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

    @Test
    func recognizesOnlyCommandKAsActionsShortcut() {
        #expect(SearchKeyboardMapper.isActionsShortcut(charactersIgnoringModifiers: "k", modifierFlags: .command))
        #expect(!SearchKeyboardMapper.isActionsShortcut(charactersIgnoringModifiers: "k", modifierFlags: []))
        #expect(!SearchKeyboardMapper.isActionsShortcut(charactersIgnoringModifiers: "k", modifierFlags: [.command, .shift]))
        #expect(!SearchKeyboardMapper.isActionsShortcut(charactersIgnoringModifiers: "j", modifierFlags: .command))
    }

    @Test(arguments: [false, true]) @MainActor
    func panelLeavesMarkedTextKeysToInputMethod(useSearchField: Bool) throws {
        let panel = SearchPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100),
            styleMask: [.nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        defer { panel.close() }
        let editor: NSTextView
        if useSearchField {
            let field = NSSearchField(frame: panel.contentView!.bounds)
            panel.contentView = field
            #expect(panel.makeFirstResponder(field))
            editor = try #require(field.currentEditor() as? NSTextView)
        } else {
            editor = NSTextView(frame: panel.contentView!.bounds)
            panel.contentView = editor
            #expect(panel.makeFirstResponder(editor))
        }
        var movements: [Int] = []
        var executions = 0
        var dismissals = 0
        var actions = 0
        panel.onMoveSelection = { movements.append($0) }
        panel.onReturn = { executions += 1 }
        panel.onEscape = { dismissals += 1 }
        panel.onToggleActions = { actions += 1 }
        editor.setMarkedText("恢复", selectedRange: NSRange(location: 2, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(editor.hasMarkedText())
        for (code, text, modifiers) in [(UInt16(125), "", NSEvent.ModifierFlags()),
            (126, "", []), (36, "\r", []), (53, "\u{1b}", []), (40, "k", .command)] {
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
                modifierFlags: modifiers, timestamp: 0, windowNumber: panel.windowNumber,
                context: nil, characters: text, charactersIgnoringModifiers: text,
                isARepeat: false, keyCode: code))
            #expect(!panel.handleCommandKey(event))
        }
        #expect(movements.isEmpty && executions == 0 && dismissals == 0 && actions == 0)
        editor.unmarkText()
        let down = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber, context: nil,
            characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 125))
        #expect(panel.handleCommandKey(down))
        #expect(movements == [1])
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
