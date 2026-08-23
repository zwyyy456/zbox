import Foundation
import Observation

nonisolated enum TextLookupSelectionMode: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case shortcutRequired
    case off

    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatic: String(localized: "Automatic")
        case .shortcutRequired: String(localized: "Shortcut Required")
        case .off: String(localized: "Off")
        }
    }
}

nonisolated enum TextLookupShortcutPreset: String, CaseIterable, Identifiable, Sendable {
    case optionC
    case doubleOption

    var id: String { rawValue }

    var label: String {
        switch self {
        case .optionC: "⌥C"
        case .doubleOption: String(localized: "Double-tap ⌥")
        }
    }

    var hotkey: Hotkey? {
        switch self {
        case .optionC: Hotkey(keyCode: 8, modifiers: 1 << 11)
        case .doubleOption: nil
        }
    }
}

@MainActor
@Observable
final class TextLookupSettingsStore {
    static let defaultExcludedApplications: Set<String> = [
        "tech.hyperseek.zbox",
        "tech.hyperseek.flashdict",
        "tech.hyperseek.flashdict.dev",
    ]

    private enum Key {
        static let enabled = "plugin.text-lookup.enabled"
        static let selectionMode = "plugin.text-lookup.selection-mode"
        static let shortcut = "plugin.text-lookup.shortcut"
        static let clipboardFallback = "plugin.text-lookup.clipboard-fallback"
        static let targetLanguage = "plugin.text-lookup.target-language"
        static let excludedApplications = "plugin.text-lookup.excluded-applications"
    }

    private let defaults: UserDefaults

    private(set) var isEnabled: Bool
    private(set) var selectionMode: TextLookupSelectionMode
    private(set) var shortcut: TextLookupShortcutPreset
    private(set) var isClipboardFallbackEnabled: Bool
    private(set) var targetLanguageIdentifier: String
    private(set) var excludedApplicationBundleIdentifiers: Set<String>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Key.enabled)
        selectionMode = defaults.string(forKey: Key.selectionMode)
            .flatMap(TextLookupSelectionMode.init(rawValue:)) ?? .automatic
        shortcut = defaults.string(forKey: Key.shortcut)
            .flatMap(TextLookupShortcutPreset.init(rawValue:)) ?? .optionC
        isClipboardFallbackEnabled = defaults.bool(forKey: Key.clipboardFallback)
        targetLanguageIdentifier = defaults.string(forKey: Key.targetLanguage)
            ?? Locale.preferredLanguages.first
            ?? "en"

        if let stored = defaults.stringArray(forKey: Key.excludedApplications) {
            excludedApplicationBundleIdentifiers = Set(stored)
        } else {
            excludedApplicationBundleIdentifiers = Self.defaultExcludedApplications
        }
    }

    func setEnabled(_ value: Bool) {
        isEnabled = value
        defaults.set(value, forKey: Key.enabled)
    }

    func setSelectionMode(_ value: TextLookupSelectionMode) {
        selectionMode = value
        defaults.set(value.rawValue, forKey: Key.selectionMode)
    }

    func setShortcut(_ value: TextLookupShortcutPreset) {
        shortcut = value
        defaults.set(value.rawValue, forKey: Key.shortcut)
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
        guard !Self.defaultExcludedApplications.contains(bundleIdentifier) else { return }
        excludedApplicationBundleIdentifiers.remove(bundleIdentifier)
        persistExcludedApplications()
    }

    private func persistExcludedApplications() {
        defaults.set(excludedApplicationBundleIdentifiers.sorted(), forKey: Key.excludedApplications)
    }
}
