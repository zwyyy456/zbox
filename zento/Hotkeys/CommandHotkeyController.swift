import Foundation
import Observation

@MainActor @Observable
final class CommandHotkeyController {
    private let store: HotkeyConfigurationStore
    private let hotkeyRegistrar: any HotkeyRegistering
    @ObservationIgnored private let applyRegistrations: () throws -> Void
    @ObservationIgnored private let recordingChanged: (Bool) -> Void
    private(set) var rootSearchHotkey: Hotkey
    private(set) var commandHotkeys: [CommandID: Hotkey] = [:]
    var rootSearchHotkeyError: String?
    var commandHotkeyErrors: [CommandID: String] = [:]
    var shortcutRegistrationError: String?
    private var isRecordingShortcut = false
    init(store: HotkeyConfigurationStore, registrar: any HotkeyRegistering,
         applyRegistrations: @escaping () throws -> Void, recordingChanged: @escaping (Bool) -> Void) {
        self.applyRegistrations = applyRegistrations
        self.recordingChanged = recordingChanged
        self.store = store
        hotkeyRegistrar = registrar
        rootSearchHotkey = store.rootSearchHotkey()
    }
    func setRootSearchHotkey(_ hotkey: Hotkey) {
        let previous = rootSearchHotkey
        rootSearchHotkeyError = nil

        do {
            try HotkeyValidator.validateUserShortcut(hotkey)
            // Resume the old registrations before replacing them so failure can roll back.
            if isRecordingShortcut {
                try hotkeyRegistrar.setSuspended(false)
            }
            rootSearchHotkey = hotkey
            try applyRegistrations()
            store.setRootSearchHotkey(hotkey)
            shortcutRegistrationError = nil
        } catch {
            rootSearchHotkey = previous
            rootSearchHotkeyError = error.localizedDescription
        }
    }

    func reportInvalidRootSearchHotkey(_ message: String) {
        rootSearchHotkeyError = message
    }

    func setCommandHotkey(_ hotkey: Hotkey?, for commandID: CommandID) {
        let previous = commandHotkeys[commandID]
        commandHotkeyErrors[commandID] = nil

        do {
            if let hotkey {
                try HotkeyValidator.validateUserShortcut(hotkey)
            }
            if isRecordingShortcut {
                try hotkeyRegistrar.setSuspended(false)
            }
            commandHotkeys[commandID] = hotkey
            try applyRegistrations()
            store.setCommandHotkey(hotkey, for: commandID)
            shortcutRegistrationError = nil
        } catch {
            commandHotkeys[commandID] = previous
            commandHotkeyErrors[commandID] = error.localizedDescription
        }
    }

    func reportInvalidCommandHotkey(_ message: String, for commandID: CommandID) {
        commandHotkeyErrors[commandID] = message
    }

    func setShortcutRecordingActive(_ isActive: Bool) {
        guard isActive != isRecordingShortcut else { return }
        isRecordingShortcut = isActive
        recordingChanged(isActive)

        do {
            try hotkeyRegistrar.setSuspended(isActive)
            shortcutRegistrationError = nil
        } catch {
            shortcutRegistrationError = error.localizedDescription
        }
    }

    func loadCommands(_ ids: [CommandID]) {
        commandHotkeys.merge(store.commandHotkeys(for: ids)) { current, _ in current }
        commandHotkeys.merge(store.applicationHotkeys()) { current, _ in current }
    }

    func forget(_ id: CommandID) {
        commandHotkeys[id] = nil
        commandHotkeyErrors[id] = nil
        store.setCommandHotkey(nil, for: id)
    }

    func validate(targets: [CommandShortcutTarget], textLookupTriggers: TextLookupTriggers,
                  textLookupEnabled: Bool) throws {
        var assignments = [
            HotkeyAssignment(owner: String(localized: "Root Search"), hotkey: rootSearchHotkey),
        ] + targets.map { target in
            HotkeyAssignment(owner: target.title, hotkey: commandHotkeys[target.id])
        }
        if textLookupEnabled {
            try textLookupTriggers.validate()
            var lookupHotkeys: Set<Hotkey> = []
            for (owner, shortcut) in textLookupTriggers.activeShortcuts {
                if let hotkey = shortcut.hotkey, lookupHotkeys.insert(hotkey).inserted {
                    assignments.append(HotkeyAssignment(owner: owner, hotkey: hotkey))
                }
            }
        }
        try HotkeyValidator.validate(assignments)
    }

    func setApplicationConfiguration(alias: String, hotkey: Hotkey?, for id: CommandID, aliasStore: CommandAliasStore) throws {
        try aliasStore.validate(alias, for: id)
        if let hotkey { try HotkeyValidator.validateUserShortcut(hotkey) }
        let previous = commandHotkeys[id]
        commandHotkeys[id] = hotkey
        do {
            try applyRegistrations()
        } catch {
            commandHotkeys[id] = previous
            throw error
        }
        // No suspension point between validation and commit.
        try aliasStore.set(alias, for: id)
        store.setCommandHotkey(hotkey, for: id)
        commandHotkeyErrors[id] = nil
        shortcutRegistrationError = nil
    }

}
