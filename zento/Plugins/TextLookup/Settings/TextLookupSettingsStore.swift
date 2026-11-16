import Foundation
import Observation

nonisolated struct TextLookupShortcut: Codable, Equatable, Sendable {
    var keyCode: UInt32?
    var modifiers: UInt32

    var hotkey: Hotkey? { keyCode.map { Hotkey(keyCode: $0, modifiers: modifiers) } }
    var label: String {
        if let hotkey { return HotkeyFormatter.displayName(for: hotkey) }
        return [(HotkeyModifiers.control, "⌃"), (HotkeyModifiers.option, "⌥"),
                (HotkeyModifiers.shift, "⇧"), (HotkeyModifiers.command, "⌘")]
            .filter { modifiers & $0.0 != 0 }.map(\.1).joined()
    }
}

nonisolated struct TextLookupTriggers: Codable, Equatable, Sendable {
    var doubleClickEnabled = true
    var doubleClickRequiresShortcut = false
    var doubleClickShortcut = TextLookupShortcut(modifiers: HotkeyModifiers.option)
    var dragEnabled = true
    var dragRequiresShortcut = true
    var dragShortcut = TextLookupShortcut(keyCode: 2, modifiers: HotkeyModifiers.option)
    var pointerEnabled = true
    var pointerShortcut = TextLookupShortcut(modifiers: HotkeyModifiers.option)

    var activeShortcuts: [(String, TextLookupShortcut)] {
        var result: [(String, TextLookupShortcut)] = []
        if doubleClickEnabled && doubleClickRequiresShortcut { result.append((String(localized: "Double-click Lookup"), doubleClickShortcut)) }
        if dragEnabled && dragRequiresShortcut { result.append((String(localized: "Drag Selection Lookup"), dragShortcut)) }
        if pointerEnabled { result.append((String(localized: "Pointer Lookup"), pointerShortcut)) }
        return result
    }

    func validate() throws {
        if doubleClickEnabled && doubleClickRequiresShortcut && dragEnabled && dragRequiresShortcut && doubleClickShortcut == dragShortcut {
            throw HotkeyConfigurationError.conflict(String(localized: "Double-click Lookup"), String(localized: "Drag Selection Lookup"))
        }
        // Mouse down cancels a pending pointer lookup when the two share a hold.
        if dragEnabled && dragRequiresShortcut && pointerEnabled && dragShortcut == pointerShortcut {
            throw HotkeyConfigurationError.conflict(String(localized: "Drag Selection Lookup"), String(localized: "Pointer Lookup"))
        }
    }
}

nonisolated enum TextLookupDictionarySource: String, Codable, CaseIterable, Identifiable, Sendable {
    case system, flashDict
    var id: String { rawValue }
}

@MainActor
@Observable
final class TextLookupSettingsStore {
    private enum Key {
        static let enabled = "plugin.text-lookup.enabled"
        static let triggers = "plugin.text-lookup.triggers"
        static let doubleClickFallback = "plugin.text-lookup.double-click-fallback"
        static let localOCR = "plugin.text-lookup.local-ocr"
        static let clipboardFallback = "plugin.text-lookup.clipboard-fallback"
        static let sourceLanguage = "plugin.text-lookup.source-language"
        static let targetLanguage = "plugin.text-lookup.target-language"
        static let excludedApplications = "plugin.text-lookup.excluded-applications"
    }

    private let defaults: UserDefaults
    let translation: TextLookupTranslationSettings
    private(set) var dictionarySource: TextLookupDictionarySource

    private(set) var isEnabled: Bool
    private(set) var triggers: TextLookupTriggers
    private(set) var isDoubleClickFallbackEnabled: Bool
    private(set) var isLocalOCREnabled: Bool
    private(set) var isClipboardFallbackEnabled: Bool
    private(set) var sourceLanguageIdentifier: String
    private(set) var targetLanguageIdentifier: String
    private(set) var excludedApplicationBundleIdentifiers: Set<String>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        translation = TextLookupTranslationSettings(defaults: defaults)
        let sourceKey = "plugin.text-lookup.dictionary-source"
        if let raw = defaults.string(forKey: sourceKey), let source = TextLookupDictionarySource(rawValue: raw) {
            dictionarySource = source
        } else {
            let initialSource: TextLookupDictionarySource = defaults.object(forKey: Key.enabled) != nil || defaults.object(forKey: Key.triggers) != nil ? .flashDict : .system
            dictionarySource = initialSource
            defaults.set(initialSource.rawValue, forKey: sourceKey)
        }
        isEnabled = defaults.bool(forKey: Key.enabled)
        if let data = defaults.data(forKey: Key.triggers),
           let saved = try? JSONDecoder().decode(TextLookupTriggers.self, from: data) {
            triggers = saved
        } else {
            var migrated = TextLookupTriggers()
            let legacyMode = defaults.string(forKey: "plugin.text-lookup.selection-mode")
            migrated.doubleClickEnabled = legacyMode != "off"
            migrated.dragEnabled = legacyMode != "off"
            if let legacyMode { migrated.dragRequiresShortcut = legacyMode == "shortcutRequired" }
            triggers = migrated
        }
        isDoubleClickFallbackEnabled = (defaults.object(forKey: Key.doubleClickFallback) as? Bool) ?? true
        isLocalOCREnabled = (defaults.object(forKey: Key.localOCR) as? Bool) ?? true
        isClipboardFallbackEnabled = (defaults.object(forKey: Key.clipboardFallback) as? Bool) ?? true
        sourceLanguageIdentifier = defaults.string(forKey: Key.sourceLanguage) ?? ""
        targetLanguageIdentifier = defaults.string(forKey: Key.targetLanguage)
            ?? Locale.preferredLanguages.first
            ?? "en"

        let stored = Set(defaults.stringArray(forKey: Key.excludedApplications) ?? [])
        if defaults.bool(forKey: "plugin.text-lookup.removed-default-exclusions") {
            excludedApplicationBundleIdentifiers = stored
        } else {
            excludedApplicationBundleIdentifiers = stored.subtracting([
                "tech.hyperseek.zento", "tech.hyperseek.flashdict", "tech.hyperseek.flashdict.dev",
            ])
            defaults.set(excludedApplicationBundleIdentifiers.sorted(), forKey: Key.excludedApplications)
            defaults.set(true, forKey: "plugin.text-lookup.removed-default-exclusions")
        }
    }

    func setDictionarySource(_ source: TextLookupDictionarySource) {
        dictionarySource = source
        defaults.set(source.rawValue, forKey: "plugin.text-lookup.dictionary-source")
    }

    func setEnabled(_ value: Bool) {
        isEnabled = value
        defaults.set(value, forKey: Key.enabled)
    }

    func setTriggers(_ value: TextLookupTriggers) {
        triggers = value
        defaults.set(try? JSONEncoder().encode(value), forKey: Key.triggers)
    }

    func setDoubleClickFallbackEnabled(_ value: Bool) {
        isDoubleClickFallbackEnabled = value
        defaults.set(value, forKey: Key.doubleClickFallback)
    }

    func setLocalOCREnabled(_ value: Bool) {
        isLocalOCREnabled = value
        defaults.set(value, forKey: Key.localOCR)
    }

    func setClipboardFallbackEnabled(_ value: Bool) {
        isClipboardFallbackEnabled = value
        defaults.set(value, forKey: Key.clipboardFallback)
    }

    func setSourceLanguageIdentifier(_ value: String) {
        sourceLanguageIdentifier = value
        defaults.set(value, forKey: Key.sourceLanguage)
    }

    func setTargetLanguageIdentifier(_ value: String) {
        targetLanguageIdentifier = value
        defaults.set(value, forKey: Key.targetLanguage)
    }

    func addExcludedApplication(_ bundleIdentifier: String) {
        let value = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        excludedApplicationBundleIdentifiers.insert(value)
        persistExcludedApplications()
    }

    func removeExcludedApplication(_ bundleIdentifier: String) {
        excludedApplicationBundleIdentifiers.remove(bundleIdentifier)
        persistExcludedApplications()
    }

    private func persistExcludedApplications() {
        defaults.set(excludedApplicationBundleIdentifiers.sorted(), forKey: Key.excludedApplications)
    }
}
