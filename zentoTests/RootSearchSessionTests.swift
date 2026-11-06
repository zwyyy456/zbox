import Foundation
import Testing
@testable import zento

@MainActor
struct RootSearchSessionTests {
    @Test func arrowNavigationMovesTheSingleSelectionAfterChineseQuery() throws {
        let suite = "RootSearchSessionTests.navigation.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = RootSearchSession(defaults: defaults, aliases: CommandAliasStore(defaults: defaults))
        session.descriptors = ["window.restore", "workspace.restore"].map {
            CommandDescriptor(id: CommandID($0), title: "恢复", subtitle: nil, keywords: [])
        }
        session.searchQuery = "恢复"
        let results = session.searchResults
        #expect(results.count == 2)
        #expect(session.selectedSearchMatch?.id == results[0].id)
        session.moveSelection(by: 1)
        #expect(session.selectedSearchMatch?.id == results[1].id)
        session.moveSelection(by: 1)
        #expect(session.selectedSearchMatch?.id == results[1].id)
        session.moveSelection(by: -1)
        #expect(session.selectedSearchMatch?.id == results[0].id)
    }

    @Test func queryChangeResetsSelectionAndActionsAndRecentCommandsPersist() throws {
        let suite = "RootSearchSessionTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let aliases = CommandAliasStore(defaults: defaults)
        let model = RootSearchSession(defaults: defaults, aliases: aliases)
        let id = CommandID("test.command")
        model.descriptors = [CommandDescriptor(id: id, title: "Example", subtitle: nil, keywords: [])]
        model.recordRecentCommand(id)
        model.select(id)
        model.isShowingRootSearchActions = true
        model.searchQuery = "example"
        #expect(model.selectedCommandID == nil)
        #expect(!model.isShowingRootSearchActions)
        #expect(model.selectedSearchMatch?.id == id)
        let restored = RootSearchSession(defaults: defaults, aliases: aliases)
        #expect(restored.recentCommandIDs == [id])
        model.clearRecentCommands()
        #expect(RootSearchSession(defaults: defaults, aliases: aliases).recentCommandIDs.isEmpty)
    }
}
