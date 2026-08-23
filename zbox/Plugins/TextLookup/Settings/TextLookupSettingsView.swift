import SwiftUI

struct TextLookupSettingsView: View {
    let environment: AppEnvironment
    @State private var excludedBundleIdentifier = ""

    private let commonTargetLanguages = ["zh-Hans", "en", "ja", "ko", "fr", "de", "es"]

    var body: some View {
        @Bindable var plugin = environment.textLookupPlugin
        @Bindable var settings = plugin.settings

        Section("Text Lookup") {
            Toggle(
                "Enable Text Lookup",
                isOn: Binding(
                    get: { settings.isEnabled },
                    set: { environment.setTextLookupEnabled($0) }
                )
            )
            if let message = plugin.statusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Group {
                Picker(
                "Selection Trigger",
                selection: Binding(
                    get: { settings.selectionMode },
                    set: { settings.setSelectionMode($0) }
                )
                ) {
                    ForEach(TextLookupSelectionMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }

                Picker(
                "Lookup Shortcut",
                selection: Binding(
                    get: { settings.shortcut },
                    set: { environment.setTextLookupShortcut($0) }
                )
                ) {
                    ForEach(TextLookupShortcutPreset.allCases) { shortcut in
                        Text(shortcut.label).tag(shortcut)
                    }
                }

                Toggle(
                "Clipboard Compatibility Mode",
                isOn: Binding(
                    get: { settings.isClipboardFallbackEnabled },
                    set: { settings.setClipboardFallbackEnabled($0) }
                )
                )
                Text("When Accessibility cannot read an existing selection, zbox may briefly simulate Copy and restore the clipboard if it has not changed. Pointer lookup never uses the clipboard.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker(
                "Translation Language",
                selection: Binding(
                    get: { settings.targetLanguageIdentifier },
                    set: { settings.setTargetLanguageIdentifier($0) }
                )
                ) {
                    ForEach(targetLanguageChoices, id: \.self) { identifier in
                        Text(languageName(identifier)).tag(identifier)
                    }
                }

                LabeledContent(
                    "Accessibility",
                    value: environment.isAccessibilityTrusted
                        ? String(localized: "Granted")
                        : String(localized: "Required")
                )

                HStack {
                    Button("Request Permission") {
                        environment.requestAccessibilityPermission()
                    }
                    Button("Open System Settings") {
                        environment.openAccessibilitySettings()
                    }
                }
                Text("Text Lookup reads selected text or text under the pointer only when triggered. Captured text stays in the current popup unless you create a FlashDict card. It does not use Screen Recording or keep lookup history.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Excluded Applications")
                    ForEach(settings.excludedApplicationBundleIdentifiers.sorted(), id: \.self) { identifier in
                        HStack {
                            Text(identifier)
                                .font(.caption.monospaced())
                            Spacer()
                            if !TextLookupSettingsStore.defaultExcludedApplications.contains(identifier) {
                                Button("Remove") {
                                    settings.removeExcludedApplication(identifier)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }

                    HStack {
                        TextField("Application bundle identifier", text: $excludedBundleIdentifier)
                        Button("Add") {
                            settings.addExcludedApplication(excludedBundleIdentifier)
                            excludedBundleIdentifier = ""
                        }
                        .disabled(excludedBundleIdentifier.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .disabled(!settings.isEnabled)
        }
    }

    private var targetLanguageChoices: [String] {
        [environment.textLookupPlugin.settings.targetLanguageIdentifier] + commonTargetLanguages.filter {
            $0 != environment.textLookupPlugin.settings.targetLanguageIdentifier
        }
    }

    private func languageName(_ identifier: String) -> String {
        Locale.current.localizedString(forIdentifier: identifier) ?? identifier
    }
}
