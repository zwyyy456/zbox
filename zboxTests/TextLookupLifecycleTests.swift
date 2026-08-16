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
