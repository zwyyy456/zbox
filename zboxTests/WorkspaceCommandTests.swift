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

    @Test func cancelledRestoreDoesNotAccessApplicationsOrPublishResults() async throws {
        let entry = WorkspaceEntry(bundleID: "test.workspace.nonexistent", applicationName: "Test",
            applicationURL: URL(filePath: "/Applications/WorkspaceTestDoesNotExist.app"),
            displayID: "display", displayName: "Display", frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        var reported = false
        let task = Task { @MainActor in
            try await WorkspaceRestorer().restore(WorkspaceLayout(name: "Test", entries: [entry]), mapping: [:]) { _ in
                reported = true
            }
        }
        task.cancel()
        do {
            try await task.value
            Issue.record("Expected cancellation before platform access")
        } catch is CancellationError {
            #expect(!reported)
        }
    }

    @Test func displayMatchingRequiresOneExactIdentity() {
        let first = WorkspaceDisplay(id: "first", name: "Monitor", frame: .zero, visibleFrame: .zero)
        let second = WorkspaceDisplay(id: "second", name: "Monitor", frame: .zero, visibleFrame: .zero)
        #expect(WorkspaceDisplay.matching("first", in: [first, second])?.id == "first")
        #expect(WorkspaceDisplay.matching("missing", in: [first, second]) == nil)
        #expect(WorkspaceDisplay.matching("first", in: [first, first]) == nil)
    }
}
