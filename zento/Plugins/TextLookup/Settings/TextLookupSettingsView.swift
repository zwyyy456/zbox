import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct TextLookupSettingsView: View {
    let environment: AppEnvironment
    @State private var recordingError: String?
    @State private var applicationSelectionError: String?

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
            if let message = recordingError ?? environment.textLookupError ?? plugin.statusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Group {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Double-click Lookup", isOn: triggerBinding(\.doubleClickEnabled))
                    if settings.triggers.doubleClickEnabled {
                        Picker("Trigger", selection: triggerBinding(\.doubleClickRequiresShortcut)) {
                            Text("Double-click directly").tag(false)
                            Text("Hold shortcut, then double-click").tag(true)
                        }
                        if settings.triggers.doubleClickRequiresShortcut { shortcutRecorder(\.doubleClickShortcut, title: "Double-click Lookup") }
                    }
                    Divider()
                    Toggle("Drag Selection Lookup", isOn: triggerBinding(\.dragEnabled))
                    if settings.triggers.dragEnabled {
                        Picker("Trigger", selection: triggerBinding(\.dragRequiresShortcut)) {
                            Text("Look up immediately after selection").tag(false)
                            Text("Press shortcut after selection").tag(true)
                        }
                        if settings.triggers.dragRequiresShortcut { shortcutRecorder(\.dragShortcut, title: "Drag Selection Lookup") }
                    }
                    Divider()
                    Toggle("Pointer Lookup", isOn: triggerBinding(\.pointerEnabled))
                    if settings.triggers.pointerEnabled {
                        Text("Point at a word and hold the shortcut for 500 ms to look it up.")
                            .font(.caption).foregroundStyle(.secondary)
                        shortcutRecorder(\.pointerShortcut, title: "Pointer Lookup")
                    }
                }

                Toggle(
                "Clipboard Compatibility Mode",
                isOn: Binding(
                    get: { settings.isClipboardFallbackEnabled },
                    set: { settings.setClipboardFallbackEnabled($0) }
                )
                )
                Text("When Accessibility cannot read an existing selection, Zento may briefly simulate Copy and restore the clipboard if it has not changed. Pointer lookup never uses the clipboard.")
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

                AccessibilityPermissionRow(isTrusted: environment.isAccessibilityTrusted,
                                           request: environment.requestAccessibilityPermission,
                                           openSettings: environment.openAccessibilitySettings)
                Text("Text Lookup reads selected text or text under the pointer only when triggered. Captured text stays in the current popup unless you create a FlashDict card. It does not use Screen Recording or keep lookup history.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Excluded Applications")
                    ForEach(settings.excludedApplicationBundleIdentifiers.sorted(), id: \.self) { identifier in
                        HStack {
                            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                    .resizable()
                                    .frame(width: 20, height: 20)
                                    .accessibilityHidden(true)
                                Text(FileManager.default.displayName(atPath: url.path))
                            } else {
                                Text(identifier)
                            }
                            Spacer()
                            Group {
                                Button("Remove") {
                                    settings.removeExcludedApplication(identifier)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }

                    Button("Add Application…", action: chooseExcludedApplication)
                    if let applicationSelectionError {
                        Text(applicationSelectionError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .disabled(!settings.isEnabled)
        }
    }

    private func chooseExcludedApplication() {
        let picker = NSOpenPanel()
        picker.allowedContentTypes = [.application]
        picker.directoryURL = URL(fileURLWithPath: "/Applications")
        picker.allowsMultipleSelection = false
        picker.canChooseDirectories = false
        guard picker.runModal() == .OK, let url = picker.url else { return }
        guard let identifier = Bundle(url: url)?.bundleIdentifier, !identifier.isEmpty else {
            applicationSelectionError = String(localized: "The selected application has no bundle identifier.")
            return
        }
        applicationSelectionError = nil
        environment.textLookupPlugin.settings.addExcludedApplication(identifier)
    }

    private func triggerBinding<Value>(_ keyPath: WritableKeyPath<TextLookupTriggers, Value>) -> Binding<Value> {
        Binding(get: { environment.textLookupPlugin.settings.triggers[keyPath: keyPath] }, set: { value in
            var configuration = environment.textLookupPlugin.settings.triggers
            configuration[keyPath: keyPath] = value
            recordingError = nil
            environment.setTextLookupTriggers(configuration)
        })
    }

    private func shortcutRecorder(_ keyPath: WritableKeyPath<TextLookupTriggers, TextLookupShortcut>, title: String) -> some View {
        let binding = triggerBinding(keyPath)
        let shortcut = binding.wrappedValue
        return LabeledContent("Shortcut") {
            ShortcutRecorder(hotkey: shortcut.hotkey, allowsClearing: false,
                accessibilityLabel: title,
                onChange: { if let value = $0 { binding.wrappedValue = TextLookupShortcut(keyCode: value.keyCode, modifiers: value.modifiers) } },
                onInvalid: { recordingError = $0 },
                onRecordingChanged: environment.setShortcutRecordingActive,
                modifierOnly: shortcut.keyCode == nil ? shortcut.modifiers : nil,
                onModifierOnly: { binding.wrappedValue = TextLookupShortcut(modifiers: $0) })
                .frame(width: 140)
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
