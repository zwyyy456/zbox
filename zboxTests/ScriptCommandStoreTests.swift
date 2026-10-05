import Foundation
import Testing
@testable import zbox

@MainActor
struct ScriptCommandStoreTests {
    @Test func preservesArgumentsAndProtectsUnreadableConfiguration() throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let script = folder.appending(path: "example script.sh")
        try Data("exit 0".utf8).write(to: script)
        var item = ScriptCommand()
        item.name = "Example"
        item.path = script.path
        item.arguments = ["a b", "$(touch SHOULD_NOT_EXIST)", "", "中文"]
        item.parameters = [ScriptParameter(name: "Argument")]
        let invocation = try item.invocation(values: ["; exit 1"])
        #expect(invocation.arguments == ["-f", script.path] + item.arguments + ["; exit 1"])
        #expect(invocation.directory == folder.path)
        #expect(throws: ScriptCommandError.self) { try item.invocation(values: [""]) }
        let url = folder.appending(path: "commands.json")
        let store = ScriptCommandStore(url: url)
        try store.save(item)
        let id = item.commandID
        item.name = "Renamed"
        try store.save(item)
        #expect(ScriptCommandStore(url: url).items.first?.commandID == id)
        try Data("invalid".utf8).write(to: url)
        let broken = ScriptCommandStore(url: url)
        #expect(throws: ScriptCommandError.self) { try broken.save(item) }
        #expect(try String(contentsOf: url, encoding: .utf8) == "invalid")
    }
}
