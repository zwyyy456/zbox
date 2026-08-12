import Foundation
import Testing
@testable import zbox

@MainActor
struct HotkeyConfigurationTests {
    @Test
    func persistsRootAndCommandPresets() throws {
        let suiteName = "HotkeyConfigurationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let commandID = CommandID("window.left-half")
        var store = HotkeyConfigurationStore(defaults: defaults)
        #expect(store.rootSearchPreset() == .controlOptionSpace)
        #expect(store.commandPreset(for: commandID) == .none)

        store.setRootSearchPreset(.commandShiftSpace)
        store.setCommandPreset(.controlOptionLeft, for: commandID)
        store = HotkeyConfigurationStore(defaults: defaults)

        #expect(store.rootSearchPreset() == .commandShiftSpace)
        #expect(store.commandPreset(for: commandID) == .controlOptionLeft)

        store.setCommandPreset(.none, for: commandID)
        #expect(store.commandPreset(for: commandID) == .none)
    }

    @Test
    func detectsInternalConflictsAndIgnoresUnassignedCommands() {
        let assignments = [
            HotkeyAssignment(owner: "Root Search", preset: .controlOptionSpace),
            HotkeyAssignment(owner: "Left Half", preset: .controlOptionSpace),
            HotkeyAssignment(owner: "Right Half", preset: .none),
        ]

        do {
            try HotkeyValidator.validate(assignments)
            Issue.record("Expected duplicate shortcuts to fail validation")
        } catch {
            #expect(
                error as? HotkeyConfigurationError
                    == .conflict("Root Search", "Left Half")
            )
        }
    }

    @Test
    func acceptsDistinctShortcuts() throws {
        try HotkeyValidator.validate([
            HotkeyAssignment(owner: "Root Search", preset: .controlOptionSpace),
            HotkeyAssignment(owner: "Left Half", preset: .controlOptionLeft),
            HotkeyAssignment(owner: "Right Half", preset: .controlOptionRight),
            HotkeyAssignment(owner: "Maximize", preset: .none),
        ])
    }
}
