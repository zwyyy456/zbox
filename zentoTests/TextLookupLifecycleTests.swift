import Foundation
import CoreGraphics
import Testing
@testable import zento

@MainActor
struct TextLookupLifecycleTests {
    @Test
    func settingsPersistIndependentTriggersAndRemoveOnlyLegacyExclusions() throws {
        let suiteName = "TextLookupLifecycleTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(["tech.hyperseek.zento", "tech.hyperseek.flashdict", "tech.hyperseek.flashdict.dev", "com.example.Reader"],
                     forKey: "plugin.text-lookup.excluded-applications")
        var store = TextLookupSettingsStore(defaults: defaults)
        #expect(!store.isEnabled)
        #expect(store.triggers == TextLookupTriggers())
        #expect(store.excludedApplicationBundleIdentifiers == ["com.example.Reader"])
        var configuration = store.triggers
        configuration.doubleClickRequiresShortcut = true
        configuration.dragRequiresShortcut = true
        configuration.pointerShortcut = TextLookupShortcut(keyCode: 35, modifiers: HotkeyModifiers.control)
        store.setTriggers(configuration)
        store.addExcludedApplication("tech.hyperseek.zento")
        store = TextLookupSettingsStore(defaults: defaults)
        #expect(store.triggers == configuration)
        #expect(store.excludedApplicationBundleIdentifiers.contains("tech.hyperseek.zento"))
        store.removeExcludedApplication("tech.hyperseek.zento")
        #expect(!store.excludedApplicationBundleIdentifiers.contains("tech.hyperseek.zento"))
    }

    @Test
    func sourceAndTargetLanguagesPersistIndependently() throws {
        let suite = "TextLookupLifecycleTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = TextLookupSettingsStore(defaults: defaults)
        #expect(settings.sourceLanguageIdentifier.isEmpty)
        settings.setSourceLanguageIdentifier("en")
        settings.setTargetLanguageIdentifier("zh-Hans")
        let restored = TextLookupSettingsStore(defaults: defaults)
        #expect(restored.sourceLanguageIdentifier == "en")
        #expect(restored.targetLanguageIdentifier == "zh-Hans")
        restored.setSourceLanguageIdentifier("")
        #expect(TextLookupSettingsStore(defaults: defaults).sourceLanguageIdentifier.isEmpty)
        #expect(TextLookupSettingsStore(defaults: defaults).targetLanguageIdentifier == "zh-Hans")
    }

    @Test func dictionarySourceDefaultsAndMigrationAreExplicit() throws {
        let suite = "TextLookupSourceTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(TextLookupSettingsStore(defaults: defaults).dictionarySource == .system)
        defaults.removeObject(forKey: "plugin.text-lookup.dictionary-source")
        defaults.set(true, forKey: "plugin.text-lookup.enabled")
        let existing = TextLookupSettingsStore(defaults: defaults)
        #expect(existing.dictionarySource == .flashDict)
        existing.setDictionarySource(.system)
        #expect(TextLookupSettingsStore(defaults: defaults).dictionarySource == .system)
    }

    @Test
    func pointerRequiresFullHoldAndDoesNotRepeatUntilReleased() {
        var state = TextLookupTriggerState()
        let config = TextLookupTriggers()
        state.modifiers = HotkeyModifiers.option
        let result1 = state.keyboardChanged(configuration: config, time: 1)
        #expect(!result1)
        let result2 = state.consumePointer(at: 1.49)
        #expect(!result2)
        let result3 = state.consumePointer(at: 1.5)
        #expect(result3)
        let result4 = state.consumePointer(at: 2)
        #expect(!result4)
        _ = state.keyboardChanged(configuration: config, time: 2)
        let result5 = state.consumePointer(at: 3)
        #expect(!result5)
        state.modifiers = 0
        _ = state.keyboardChanged(configuration: config, time: 3)
        state.modifiers = HotkeyModifiers.option
        _ = state.keyboardChanged(configuration: config, time: 4)
        state.modifiers = 0
        _ = state.keyboardChanged(configuration: config, time: 4.2)
        let result6 = state.consumePointer(at: 5)
        #expect(!result6)
    }

    @Test
    func distinguishesClicksDragsAndHeldDoubleClicks() {
        var config = TextLookupTriggers()
        config.dragRequiresShortcut = false
        var state = TextLookupTriggerState()
        state.mouseDown(at: .zero, clickCount: 1, configuration: config)
        let result7 = state.mouseUp(configuration: config)
        #expect(!result7)
        state.mouseDown(at: .zero, clickCount: 2, configuration: config)
        let result8 = state.mouseUp(configuration: config)
        #expect(result8)
        config.doubleClickRequiresShortcut = true
        state.mouseDown(at: .zero, clickCount: 2, configuration: config)
        let result9 = state.mouseUp(configuration: config)
        #expect(!result9)
        state.modifiers = HotkeyModifiers.option
        _ = state.keyboardChanged(configuration: config, time: 1)
        state.mouseDown(at: .zero, clickCount: 2, configuration: config)
        let result10 = state.mouseUp(configuration: config)
        #expect(result10)
        let result11 = state.consumePointer(at: 2)
        #expect(!result11)
        state.mouseDown(at: .zero, clickCount: 1, configuration: config)
        state.mouseDragged(to: CGPoint(x: 10, y: 0))
        let result12 = state.mouseUp(configuration: config)
        #expect(result12)
        config.dragRequiresShortcut = true
        state.mouseDown(at: .zero, clickCount: 1, configuration: config)
        state.mouseDragged(to: CGPoint(x: 10, y: 0))
        let result13 = state.mouseUp(configuration: config)
        #expect(!result13)
        state.keys.insert(2)
        let result14 = state.keyboardChanged(configuration: config, time: 3)
        #expect(result14)
        let result15 = state.keyboardChanged(configuration: config, time: 4)
        #expect(!result15)
        config.pointerShortcut = config.dragShortcut
        #expect(throws: HotkeyConfigurationError.self) { try config.validate() }
    }
}
