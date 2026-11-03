import Foundation

struct HotkeyConfigurationStore {
    private enum Key {
        static let rootSearch = "hotkey.root-search"

        static func command(_ commandID: CommandID) -> String {
            "hotkey.command.\(commandID.rawValue)"
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func rootSearchHotkey() -> Hotkey {
        hotkey(forKey: Key.rootSearch) ?? .defaultRootSearch
    }

    func setRootSearchHotkey(_ hotkey: Hotkey) {
        set(hotkey, forKey: Key.rootSearch)
    }

    func commandHotkeys(for commandIDs: [CommandID]) -> [CommandID: Hotkey] {
        Dictionary(
            uniqueKeysWithValues: commandIDs.compactMap { commandID in
                hotkey(forKey: Key.command(commandID)).map { (commandID, $0) }
            }
        )
    }

    func setCommandHotkey(_ hotkey: Hotkey?, for commandID: CommandID) {
        let key = Key.command(commandID)
        guard let hotkey else {
            defaults.removeObject(forKey: key)
            return
        }
        set(hotkey, forKey: key)
    }

    private func hotkey(forKey key: String) -> Hotkey? {
        guard let value = defaults.dictionary(forKey: key),
              let keyCode = value["keyCode"] as? Int,
              let modifiers = value["modifiers"] as? Int,
              let keyCode = UInt32(exactly: keyCode),
              let modifiers = UInt32(exactly: modifiers) else {
            if defaults.object(forKey: key) != nil {
                defaults.removeObject(forKey: key)
            }
            return nil
        }
        return Hotkey(keyCode: keyCode, modifiers: modifiers)
    }

    private func set(_ hotkey: Hotkey, forKey key: String) {
        defaults.set(
            [
                "keyCode": Int(hotkey.keyCode),
                "modifiers": Int(hotkey.modifiers),
            ],
            forKey: key
        )
    }
}
