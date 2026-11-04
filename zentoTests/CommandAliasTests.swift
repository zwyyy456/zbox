import Foundation
import Testing
@testable import zento

@MainActor
struct CommandAliasTests {
    @Test func persistsAndRejectsConflictsWithoutReplacingPreviousValue() throws {
        let name = "CommandAliasTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = CommandAliasStore(defaults: defaults)
        let a = CommandID("a"), b = CommandID("b")
        try store.set(" CB ", for: a)
        try store.set("other", for: b)
        #expect(throws: CommandAliasStore.AliasError.self) { try store.set("cb", for: b) }
        #expect(throws: CommandAliasStore.AliasError.self) { try store.set("two words", for: b) }
        #expect(store.aliases[b] == "other")
        #expect(CommandAliasStore(defaults: defaults).aliases[a] == "CB")
        try store.set("", for: a)
        #expect(CommandAliasStore(defaults: defaults).aliases[a] == nil)
        store.remove(b)
        #expect(CommandAliasStore(defaults: defaults).aliases.isEmpty)
    }

    @Test func exactAliasWinsBeforeLimitAndMissingCommandsStayAbsent() {
        let a = CommandDescriptor(id: CommandID("a"), title: "cb", subtitle: nil, keywords: [])
        let b = CommandDescriptor(id: CommandID("b"), title: "Clipboard", subtitle: nil, keywords: [])
        let engine = SearchEngine()
        let aliases = [b.id: "CB", CommandID("missing"): "other"]
        #expect(engine.search(query: "cb", in: [a, b], limit: 1, aliases: aliases).first?.id == b.id)
        #expect(engine.search(query: "other", in: [a, b], limit: 8, aliases: aliases).isEmpty)
        #expect(engine.search(query: "", in: [a, b], limit: 1, aliases: aliases).first?.id == a.id)
    }
}
