import SwiftUI

struct ScreenshotSettingsView: View {
    let plugin: ScreenshotPlugin
    let onEnabledChanged: @MainActor @Sendable (Bool) -> Void
    let shortcutError: String?
    var body: some View {
        Form {
            Toggle("Enable Screenshot", isOn: Binding(get: { plugin.isEnabled }, set: onEnabledChanged))
            Text("Captures only when you run a screenshot command. Screen Recording permission is required.")
                .foregroundStyle(.secondary)
            Button("Open Screen Recording Settings", action: plugin.openScreenRecordingSettings)
            if let status = plugin.statusMessage { Text(status).foregroundStyle(.secondary) }
            if let shortcutError { SettingsErrorView(message: shortcutError) }
        }.settingsPane()
    }
}
