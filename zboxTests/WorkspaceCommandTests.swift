import Foundation
import CoreGraphics
import Testing
@testable import zbox

@MainActor
struct WorkspaceCommandTests {
    @Test func disabledWorkspaceCommandsOpenSettingsWithoutMovingWindows() async throws {
        let suite = "WorkspaceTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let plugin = WorkspacePlugin(defaults: defaults)
        let layout = WorkspaceLayout(name: "Development", entries: [])
        try plugin.store.save(layout)
        let registry = CommandRegistry()
        var openedSettings = 0
        try plugin.register(in: registry) { openedSettings += 1 }
        try await registry.execute(layout.commandID, context: CommandContext(source: .directHotkey, frontmostApplicationPID: nil))
        #expect(openedSettings == 1)
        #expect(!plugin.isRestoring)
        #expect(plugin.shortcutTargets.map(\.id) == [layout.commandID])
    }

    @Test func displayMatchingRequiresOneExactIdentity() {
        let first = WorkspaceDisplay(id: "first", name: "Monitor", frame: .zero, visibleFrame: .zero)
        let second = WorkspaceDisplay(id: "second", name: "Monitor", frame: .zero, visibleFrame: .zero)
        #expect(WorkspaceDisplay.matching("first", in: [first, second])?.id == "first")
        #expect(WorkspaceDisplay.matching("missing", in: [first, second]) == nil)
        #expect(WorkspaceDisplay.matching("first", in: [first, first]) == nil)
    }
}
