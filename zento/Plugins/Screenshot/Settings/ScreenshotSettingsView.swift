import SwiftUI

struct ScreenshotSettingsView: View {
    @Bindable var plugin: ScreenshotPlugin
    let onEnabledChanged: @MainActor @Sendable (Bool) -> Void
    let shortcutError: String?
    var body: some View {
        Form {
            Toggle("Enable Screenshot & Recording", isOn: Binding(get: { plugin.isEnabled }, set: onEnabledChanged))
            Text("Captures only when you run a screenshot or recording command. Screen Recording permission is required.")
                .foregroundStyle(.secondary)
            LabeledContent("Screen Recording") {
                Text(plugin.isScreenRecordingAuthorized ? String(localized: "Authorized") : String(localized: "Not Authorized"))
            }
            HStack {
                if !plugin.isScreenRecordingAuthorized {
                    Button("Request Permission", action: plugin.requestScreenRecordingPermission)
                }
                Button("Open Screen Recording Settings", action: plugin.openScreenRecordingSettings)
            }
            Section("After Capture") {
                Picker("Show after capture", selection: $plugin.opensEditorAfterCapture) {
                    Text("Small Preview").tag(false)
                    Text("Image Editor").tag(true)
                }
                Toggle("Automatically copy image", isOn: $plugin.automaticallyCopy)
                Toggle("Automatically save image", isOn: $plugin.automaticallySave)
                    .disabled(plugin.saveDirectory == nil)
                LabeledContent("Save folder") {
                    Text(plugin.saveDirectory?.path ?? String(localized: "Choose a folder first"))
                        .lineLimit(1).truncationMode(.middle)
                        .help(plugin.saveDirectory?.path ?? "")
                    Button("Choose Folder…", action: plugin.chooseSaveDirectory)
                }
                Picker("Format", selection: $plugin.format) {
                    ForEach(ScreenshotFormat.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                if plugin.format == .jpeg {
                    LabeledContent("JPEG quality") {
                        Slider(value: $plugin.jpegQuality, in: 0.1...1)
                        Text(plugin.jpegQuality, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit().frame(width: 45)
                    }
                }
                Text("Automatic copying and saving use the original capture. Export later edits explicitly.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ScreenshotHostingView(settings: plugin.hosting, plugin: plugin)
            if let status = plugin.statusMessage { Text(status).foregroundStyle(.secondary) }
            if let shortcutError { SettingsErrorView(message: shortcutError) }
        }.settingsPane()
        .onAppear { plugin.refreshScreenRecordingPermission() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            plugin.refreshScreenRecordingPermission()
        }
    }
}
