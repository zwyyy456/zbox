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
            LabeledContent("Screen Recording") {
                Text(plugin.isScreenRecordingAuthorized ? String(localized: "Authorized") : String(localized: "Not Authorized"))
            }
            HStack {
                if !plugin.isScreenRecordingAuthorized {
                    Button("Request Permission", action: plugin.requestScreenRecordingPermission)
                }
                Button("Open Screen Recording Settings", action: plugin.openScreenRecordingSettings)
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
