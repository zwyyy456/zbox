import Foundation
import Observation

@MainActor
@Observable
final class TextLookupPlugin: BuiltinPlugin {
    static let pluginID = BuiltinPluginID(rawValue: "text-lookup")
    static let hotkeyRegistrationID = "plugin.text-lookup.lookup"

    let id = pluginID
    private let settings: TextLookupSettingsStore
    private let hotkeyRegistrar: GlobalHotkeyRegistrar

    private(set) var isRunning = false
    private(set) var statusMessage: String?

    init(settings: TextLookupSettingsStore, hotkeyRegistrar: GlobalHotkeyRegistrar) {
        self.settings = settings
        self.hotkeyRegistrar = hotkeyRegistrar
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        do {
            try reloadConfiguration()
            statusMessage = nil
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func stop() {
        guard isRunning else { return }
        hotkeyRegistrar.unregister(id: Self.hotkeyRegistrationID)
        isRunning = false
        statusMessage = nil
    }

    func reloadConfiguration() throws {
        guard isRunning else { return }
        hotkeyRegistrar.unregister(id: Self.hotkeyRegistrationID)
        guard let hotkey = settings.shortcut.hotkey else { return }

        try hotkeyRegistrar.register(
            id: Self.hotkeyRegistrationID,
            hotkey: hotkey,
            label: settings.shortcut.label
        ) {
            // Text capture is connected in Slice 2.
        }
    }
}
