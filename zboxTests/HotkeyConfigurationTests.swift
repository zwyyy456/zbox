import Foundation
import Testing
@testable import zbox

@MainActor
struct HotkeyConfigurationTests {
    @Test
    func persistsArbitraryHotkeysAndIgnoresUnknownCommands() throws {
        let suiteName = "HotkeyConfigurationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let knownID = CommandID("window.left-half")
        let unknownID = CommandID("removed.command")
        let root = Hotkey(keyCode: 35, modifiers: HotkeyModifiers.command | HotkeyModifiers.option)
        let command = Hotkey(keyCode: 123, modifiers: HotkeyModifiers.control)
        let updatedCommand = Hotkey(keyCode: 125, modifiers: HotkeyModifiers.control)
        let unknown = Hotkey(keyCode: 124, modifiers: HotkeyModifiers.control)
        var store = HotkeyConfigurationStore(defaults: defaults)

        #expect(store.rootSearchHotkey() == .defaultRootSearch)
        #expect(store.commandHotkeys(for: [knownID]).isEmpty)

        store.setRootSearchHotkey(root)
        store.setCommandHotkey(command, for: knownID)
        store.setCommandHotkey(unknown, for: unknownID)
        store = HotkeyConfigurationStore(defaults: defaults)

        #expect(store.rootSearchHotkey() == root)
        #expect(store.commandHotkeys(for: [knownID]) == [knownID: command])
        #expect(store.commandHotkeys(for: [knownID])[unknownID] == nil)

        store.setCommandHotkey(updatedCommand, for: knownID)
        store = HotkeyConfigurationStore(defaults: defaults)
        #expect(store.commandHotkeys(for: [knownID]) == [knownID: updatedCommand])

        store.setCommandHotkey(nil, for: knownID)
        #expect(store.commandHotkeys(for: [knownID]).isEmpty)
    }

    @Test
    func discardsLegacyPresetValuesWithoutMigration() throws {
        let suiteName = "HotkeyConfigurationTests.legacy.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("commandShiftSpace", forKey: "hotkey.root-search")

        let store = HotkeyConfigurationStore(defaults: defaults)

        #expect(store.rootSearchHotkey() == .defaultRootSearch)
        #expect(defaults.object(forKey: "hotkey.root-search") == nil)
    }

    @Test
    func rejectsUnsafeUserShortcutsAndInternalConflicts() {
        let plainLetter = Hotkey(keyCode: 0, modifiers: 0)
        let modifierKey = Hotkey(keyCode: 59, modifiers: HotkeyModifiers.control)
        let duplicate = Hotkey(keyCode: 49, modifiers: HotkeyModifiers.control)

        #expect(throws: HotkeyConfigurationError.modifierRequired) {
            try HotkeyValidator.validateUserShortcut(plainLetter)
        }
        #expect(throws: HotkeyConfigurationError.modifierOnly) {
            try HotkeyValidator.validateUserShortcut(modifierKey)
        }
        #expect(throws: HotkeyConfigurationError.conflict("Root Search", "Left Half")) {
            try HotkeyValidator.validate([
                HotkeyAssignment(owner: "Root Search", hotkey: duplicate),
                HotkeyAssignment(owner: "Left Half", hotkey: duplicate),
                HotkeyAssignment(owner: "Maximize", hotkey: nil),
            ])
        }
    }

    @Test
    func registrationFailureKeepsPreviousModelAndPersistence() throws {
        let suiteName = "HotkeyConfigurationTests.rollback.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let previous = Hotkey.defaultRootSearch
        let replacement = Hotkey(
            keyCode: 35,
            modifiers: HotkeyModifiers.command | HotkeyModifiers.shift
        )
        HotkeyConfigurationStore(defaults: defaults).setRootSearchHotkey(previous)
        let registrar = FailingHotkeyRegistrar()
        let environment = AppEnvironment(defaults: defaults, hotkeyRegistrar: registrar)
        registrar.shouldFail = true

        environment.setRootSearchHotkey(replacement)

        #expect(environment.rootSearchHotkey == previous)
        #expect(HotkeyConfigurationStore(defaults: defaults).rootSearchHotkey() == previous)
    }
}

@MainActor
private final class FailingHotkeyRegistrar: HotkeyRegistering {
    var shouldFail = false

    func replace(ids: Set<String>, with requests: [HotkeyRegistrationRequest]) throws {
        if shouldFail { throw TestRegistrationError.failed }
    }

    func setSuspended(_ isSuspended: Bool) throws {}
    func unregisterAll() {}
    func unregister(id: String) {}
}

private enum TestRegistrationError: LocalizedError {
    case failed

    var errorDescription: String? { "Registration failed." }
}
