import CoreGraphics

import Foundation
import Testing
@testable import zbox

@MainActor
struct WorkspaceStoreTests {
    @Test func persistsLayoutAndKeepsIdentityWhenRenamed() throws {
        let suite = "WorkspaceTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = WorkspaceStore(defaults: defaults)
        var layout = WorkspaceLayout(name: "Development", entries: [WorkspaceEntry(
            bundleID: "test.app", applicationName: "Editor", applicationURL: URL(filePath: "/Applications/Editor.app"),
            displayID: "display", displayName: "Display", frame: CGRect(x: 0, y: 0, width: 0.5, height: 1))])
        let commandID = layout.commandID
        try store.save(layout)
        layout.name = "Writing"
        try store.save(layout)
        let reloaded = WorkspaceStore(defaults: defaults)
        #expect(reloaded.layouts == [layout])
        #expect(reloaded.layouts.first?.commandID == commandID)
        try reloaded.delete(layout.id)
        #expect(WorkspaceStore(defaults: defaults).layouts.isEmpty)
    }

    @Test func preservesUnreadableData() throws {
        let suite = "WorkspaceTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let original = Data("invalid".utf8)
        defaults.set(original, forKey: "workspace.layouts")
        let store = WorkspaceStore(defaults: defaults)
        #expect(store.errorMessage != nil)
        #expect(throws: WorkspaceError.self) {
            try store.save(WorkspaceLayout(name: "New", entries: []))
        }
        #expect(defaults.data(forKey: "workspace.layouts") == original)
    }
}
