import Foundation
import Testing
@testable import zbox

@MainActor
struct TextLookupLifecycleTests {
    @Test
    func settingsUseExpectedDefaultsAndPersistChanges() throws {
        let suiteName = "TextLookupLifecycleTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var store = TextLookupSettingsStore(defaults: defaults)
        #expect(!store.isEnabled)
        #expect(store.selectionMode == .automatic)
        #expect(store.shortcut == .optionC)
        #expect(!store.isClipboardFallbackEnabled)
        #expect(store.excludedApplicationBundleIdentifiers.contains("tech.hyperseek.zbox"))
        #expect(store.excludedApplicationBundleIdentifiers.contains("tech.hyperseek.flashdict"))

        store.setEnabled(true)
        store.setSelectionMode(.shortcutRequired)
        store.setShortcut(.doubleOption)
        store.setClipboardFallbackEnabled(true)
        store.setTargetLanguageIdentifier("ja")
        store.addExcludedApplication("com.example.Reader")
        store = TextLookupSettingsStore(defaults: defaults)

        #expect(store.isEnabled)
        #expect(store.selectionMode == .shortcutRequired)
        #expect(store.shortcut == .doubleOption)
        #expect(store.isClipboardFallbackEnabled)
        #expect(store.targetLanguageIdentifier == "ja")
        #expect(store.excludedApplicationBundleIdentifiers.contains("com.example.Reader"))
    }

    @Test
    func hostStartsAndStopsPluginIdempotently() {
        let plugin = PluginSpy()
        let host = BuiltinPluginHost(plugins: [plugin])

        host.setEnabled(true, for: plugin.id)
        host.setEnabled(true, for: plugin.id)
        #expect(plugin.startCount == 1)

        host.setEnabled(false, for: plugin.id)
        host.setEnabled(false, for: plugin.id)
        #expect(plugin.stopCount == 1)

        host.setEnabled(true, for: plugin.id)
        host.stopAll()
        host.stopAll()
        #expect(plugin.startCount == 2)
        #expect(plugin.stopCount == 2)
    }

    @Test
    func textLookupHotkeyParticipatesInConflictValidation() {
        let optionC = TextLookupShortcutPreset.optionC.hotkey

        do {
            try HotkeyValidator.validate([
                HotkeyAssignment(owner: "Existing", hotkey: optionC),
                HotkeyAssignment(owner: "Text Lookup", hotkey: optionC),
            ])
            Issue.record("Expected the duplicate Text Lookup shortcut to be rejected")
        } catch {
            #expect(
                error as? HotkeyConfigurationError
                    == .conflict("Existing", "Text Lookup")
            )
        }
    }
}

@MainActor
private final class PluginSpy: BuiltinPlugin {
    let id = BuiltinPluginID(rawValue: "spy")
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start() { startCount += 1 }
    func stop() { stopCount += 1 }
}
