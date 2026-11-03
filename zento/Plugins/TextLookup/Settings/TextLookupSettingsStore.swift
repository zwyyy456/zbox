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

@MainActor
@Observable
final class TextLookupSettingsStore {
    private enum Key {
        static let enabled = "plugin.text-lookup.enabled"
        static let triggers = "plugin.text-lookup.triggers"
        static let clipboardFallback = "plugin.text-lookup.clipboard-fallback"
        static let targetLanguage = "plugin.text-lookup.target-language"
        static let excludedApplications = "plugin.text-lookup.excluded-applications"
    }

    private let defaults: UserDefaults

    private(set) var isEnabled: Bool
    private(set) var triggers: TextLookupTriggers
    private(set) var isClipboardFallbackEnabled: Bool
    private(set) var targetLanguageIdentifier: String
    private(set) var excludedApplicationBundleIdentifiers: Set<String>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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
        isClipboardFallbackEnabled = defaults.bool(forKey: Key.clipboardFallback)
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

    func setEnabled(_ value: Bool) {
        isEnabled = value
        defaults.set(value, forKey: Key.enabled)
    }

    func setTriggers(_ value: TextLookupTriggers) {
        triggers = value
        defaults.set(try? JSONEncoder().encode(value), forKey: Key.triggers)
    }

    func setClipboardFallbackEnabled(_ value: Bool) {
        isClipboardFallbackEnabled = value
        defaults.set(value, forKey: Key.clipboardFallback)
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
