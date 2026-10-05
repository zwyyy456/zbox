import Foundation
import Testing
@testable import zbox

struct AppleShortcutsTests {
    @Test func parsesIdentityWithoutConfusingDuplicateNames() throws {
        let first = UUID(), second = UUID()
        let entries = try AppleShortcuts.parseList("Same (name) (\(first))\nSame (name) (\(second))\n")
        #expect(entries.map(\.id) == [first, second])
        #expect(entries.map(\.name) == ["Same (name)", "Same (name)"])
        #expect(throws: AppleShortcutError.self) { try AppleShortcuts.parseList("Unidentified shortcut\n") }
    }

    @Test func textIsPassedAsFileRatherThanShellArguments() throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let shortcut = AppleShortcutConfiguration(identifier: UUID(), name: "Test", acceptsText: true)
        let text = "  中文\n$(touch SHOULD_NOT_EXIST); ' \u{0}"
        let command = try AppleShortcuts.invocation(shortcut, input: text, directory: directory, timeout: 30)
        #expect(command.executable == "/usr/bin/shortcuts")
        #expect(command.arguments == ["run", shortcut.identifier.uuidString, "--output-type", "public.utf8-plain-text", "--input-path", directory.appending(path: "input.txt").path])
        #expect(try Data(contentsOf: directory.appending(path: "input.txt")) == Data(text.utf8))
        #expect(throws: AppleShortcutError.self) {
            try AppleShortcuts.invocation(shortcut, input: String(repeating: "x", count: 1_048_577), directory: directory, timeout: 30)
        }
    }

    @MainActor @Test func preservesLegacyCommandsWhenSavingShortcuts() throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "commands.json")
        let id = UUID()
        let oldData = """
        [{"id":"\(id)","name":"Existing","keywords":"test","enabled":true,"path":"/tmp/example.sh","interpreter":"/bin/zsh","directory":"","arguments":["a b"],"parameters":[],"timeout":60}]
        """
        try Data(oldData.utf8).write(to: file)
        let store = ScriptCommandStore(url: file)
        let previous = try #require(store.items.first)
        #expect(store.loadError == nil)
        #expect(previous.shortcut == nil)
        #expect(previous.commandID == CommandID("scripts.\(id.uuidString)"))
        var added = ScriptCommand()
        added.name = "New shortcut"
        added.shortcut = AppleShortcutConfiguration(identifier: UUID(), name: "Original name", acceptsText: true)
        try store.save(added)
        let restored = ScriptCommandStore(url: file)
        #expect(restored.items == [previous, added])
        added.shortcut?.name = "Renamed"
        try store.save(added)
        #expect(ScriptCommandStore(url: file).items.last?.commandID == added.commandID)
    }
}
