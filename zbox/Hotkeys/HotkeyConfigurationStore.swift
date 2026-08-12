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

    func rootSearchPreset() -> HotkeyPreset {
        preset(forKey: Key.rootSearch) ?? .controlOptionSpace
    }

    func setRootSearchPreset(_ preset: HotkeyPreset) {
        defaults.set(preset.rawValue, forKey: Key.rootSearch)
    }

    func commandPreset(for commandID: CommandID) -> HotkeyPreset {
        preset(forKey: Key.command(commandID)) ?? .none
    }

    func setCommandPreset(_ preset: HotkeyPreset, for commandID: CommandID) {
        if preset == .none {
            defaults.removeObject(forKey: Key.command(commandID))
        } else {
            defaults.set(preset.rawValue, forKey: Key.command(commandID))
        }
    }

    private func preset(forKey key: String) -> HotkeyPreset? {
        defaults.string(forKey: key).flatMap(HotkeyPreset.init(rawValue:))
    }
}
