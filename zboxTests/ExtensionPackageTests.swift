import Foundation
import Darwin
import Testing
@testable import zbox

struct ExtensionPackageTests {
    private func makePackage(at root: URL, version: String = "1.0.0") throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("""
        {"schemaVersion":1,"id":"org.example.hello","name":"Hello","version":"\(version)",
        "commands":[{"id":"hello","name":"Hello","mode":"task","entry":"main.zsh","interpreter":"/bin/zsh"}]}
        """.utf8).write(to: root.appending(path: "manifest.json"))
        try Data("print hello".utf8).write(to: root.appending(path: "main.zsh"))
    }

    @Test func installationKeepsIdentityAndInvalidUpdateLeavesOldIndex() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appending(path: "source")
        try makePackage(at: source)
        let store = ExtensionPackageStore(root: root.appending(path: "installed"))
        let first = try await store.prepare(source)
        try await store.save([first])
        try makePackage(at: source, version: "2.0.0")
        let second = try await store.prepare(source)
        #expect(first.manifest.commands[0].commandID(in: first.id) == second.manifest.commands[0].commandID(in: second.id))
        try await store.discard(second)
        try FileManager.default.removeItem(at: source.appending(path: "main.zsh"))
        await #expect(throws: (any Error).self) { try await store.prepare(source) }
        #expect(try await store.load().first?.directory == first.directory)
        #expect(FileManager.default.fileExists(atPath: store.packageURL(first).appending(path: "main.zsh").path))
    }

    @Test func rejectsLinksBeforeCopyingContent() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appending(path: "source")
        try makePackage(at: source)
        try FileManager.default.createSymbolicLink(at: source.appending(path: "outside"), withDestinationURL: root)
        let store = ExtensionPackageStore(root: root.appending(path: "installed"))
        await #expect(throws: ExtensionFailure.self) { try await store.prepare(source) }
        #expect(try await store.load().isEmpty)
    }

    @MainActor @Test func commandRegistrationFailureKeepsInstalledVersion() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appending(path: "source")
        try makePackage(at: source)
        let store = ExtensionPackageStore(root: root.appending(path: "installed"))
        let manager = ExtensionManager(coordinator: ClipboardAccessCoordinator(), store: store)
        await manager.load()
        await manager.prepare(source)
        await manager.install()
        #expect(manager.items.first?.manifest.version == "1.0.0")
        manager.applyCommands = {
            if manager.items.first?.manifest.version == "2.0.0" { throw ExtensionFailure("Registration failed") }
        }
        try makePackage(at: source, version: "2.0.0")
        await manager.prepare(source)
        await manager.install()
        #expect(manager.error != nil)
        #expect(manager.items.first?.manifest.version == "1.0.0")
        #expect(try await store.load().first?.manifest.version == "1.0.0")
        await manager.discardCandidate()
    }
    @Test func extractsDeflateAndRejectsTraversal() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appending(path: "output")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let archive = root.appending(path: "package.zip")
        try Data(base64Encoded: "UEsDBBQAAAAIANtgRV1ZkwG9DQAAAAsAAAAIAAAAbWFpbi56c2grKMrMK1HISM3JyQcAUEsBAhQDFAAAAAgA22BFXVmTAb0NAAAACwAAAAgAAAAAAAAAAAAAAIABAAAAAG1haW4uenNoUEsFBgAAAAABAAEANgAAADMAAAAAAA==")!.write(to: archive)
        let quarantine = Array("0081;00000000;zbox-test;".utf8)
        #expect(setxattr(archive.path, "com.apple.quarantine", quarantine, quarantine.count, 0, 0) == 0)
        try ExtensionArchive.extract(archive, to: destination)
        var restored = [UInt8](repeating: 0, count: 100)
        let count = getxattr(destination.appending(path: "main.zsh").path, "com.apple.quarantine", &restored, restored.count, 0, 0)
        #expect(count == quarantine.count && Array(restored.prefix(max(0, count))) == quarantine)
        #expect(try String(contentsOf: destination.appending(path: "main.zsh"), encoding: .utf8) == "print hello")
        try Data(base64Encoded: "UEsDBBQAAAAIANtgRV1ZkwG9DQAAAAsAAAAJAAAALi4vZXNjYXBlKyjKzCtRyEjNyckHAFBLAQIUAxQAAAAIANtgRV1ZkwG9DQAAAAsAAAAJAAAAAAAAAAAAAACAAQAAAAAuLi9lc2NhcGVQSwUGAAAAAAEAAQA3AAAANAAAAAAA")!.write(to: archive)
        #expect(throws: ExtensionFailure.self) { try ExtensionArchive.extract(archive, to: destination) }
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "escape").path))
    }

}
