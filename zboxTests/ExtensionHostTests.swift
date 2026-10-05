import ZboxExtensionProtocol
import Foundation
import Testing
@testable import zbox

@MainActor
struct ExtensionHostTests {
    private func installation() throws -> ExtensionInstallation {
        let manifest = try JSONDecoder().decode(ExtensionManifest.self, from: Data("""
        {"schemaVersion":1,"id":"org.example.host","name":"Host test","version":"1.0.0",
        "capabilities":["storage","credentials"],"settings":[{"id":"ordinary","name":"Ordinary","type":"text","defaultValue":"default"},
        {"id":"secret","name":"Secret","type":"secret"}],
        "commands":[{"id":"test","name":"Test","mode":"interactive","entry":"main.zsh","interpreter":"/bin/zsh","protocolVersion":1}]}
        """.utf8))
        return ExtensionInstallation(manifest: manifest, directory: UUID().uuidString, source: "test", enabled: true, grants: [])
    }

    @Test func deniedAndExpiredCallsCannotWriteAndSettingsExcludeSecrets() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let data = ExtensionDataStore(root: root, id: "org.example.host")
        var item = try installation()
        let context = CommandContext(source: .rootSearch, frontmostApplicationPID: nil)
        let params = ExtensionValue.object(["key": .string("result"), "value": .string("content")])
        let denied = ExtensionHostAPI(installation: item, data: data, coordinator: ClipboardAccessCoordinator(), context: context)
        await #expect(throws: ExtensionFailure.self) { try await denied.call("storage.set", params: params, expectedClipboardCount: 0) { true } }
        item.grants = ["storage"]
        let allowed = ExtensionHostAPI(installation: item, data: data, coordinator: ClipboardAccessCoordinator(), context: context)
        await #expect(throws: ExtensionFailure.self) { try await allowed.call("storage.set", params: params, expectedClipboardCount: 0) { false } }
        #expect(try await data.storage("result") == .null)
        let settings = try await allowed.call("settings.get", params: .object([:]), expectedClipboardCount: 0) { true }
        #expect(settings["ordinary"] == .string("default"))
        #expect(settings["secret"] == nil)
    }

    @Test func oldQueryCannotReplaceUIOrWriteStorage() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try """
        read -r initial
        print -r -- '{"jsonrpc":"2.0","id":"initialize","result":{"protocolVersion":1}}'
        read -r start
        print -r -- '{"jsonrpc":"2.0","method":"ui","params":{"eventID":1,"view":{"title":"initial"}}}'
        while read -r message; do
          if [[ "$message" == *'"method":"query"'* ]]; then
            print -r -- '{"jsonrpc":"2.0","method":"ui","params":{"eventID":1,"view":{"title":"stale"}}}'
            print -r -- '{"jsonrpc":"2.0","id":"old","method":"storage.set","params":{"eventID":1,"key":"stale","value":"wrong"}}'
            print -r -- '{"jsonrpc":"2.0","method":"ui","params":{"eventID":2,"view":{"title":"current"}}}'
          fi
        done
        """.write(to: root.appending(path: "main.zsh"), atomically: true, encoding: .utf8)
        var item = try installation(); item.grants = ["storage"]
        let data = ExtensionDataStore(root: root.appending(path: "data"), id: item.id)
        let context = CommandContext(source: .rootSearch, frontmostApplicationPID: nil)
        let session = ExtensionSession(command: item.manifest.commands[0], root: root,
            host: ExtensionHostAPI(installation: item, data: data, coordinator: ClipboardAccessCoordinator(), context: context))
        session.start()
        for _ in 0..<200 where session.snapshot.title != "initial" { try await Task.sleep(for: .milliseconds(10)) }
        #expect(session.snapshot.title == "initial")
        session.sendQuery("new")
        for _ in 0..<200 where session.snapshot.title != "current" { try await Task.sleep(for: .milliseconds(10)) }
        session.cancel(); await session.waitForStop()
        #expect(session.snapshot.title == "current")
        #expect(try await data.storage("stale") == .null)
    }
}
