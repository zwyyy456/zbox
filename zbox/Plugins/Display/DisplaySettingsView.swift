import SwiftUI

struct DisplaySettingsView: View {
    let environment: AppEnvironment

    var body: some View {
        let plugin = environment.displayPlugin
        Form {
            Section {
                Toggle("Enable Display", isOn: Binding(get: { plugin.isEnabled }, set: environment.setDisplayEnabled))
                Button("Refresh Displays", action: plugin.refresh)
                if let message = plugin.statusMessage { Text(message).font(.caption) }
            }
            if plugin.displays.isEmpty { Text("No displays available.").foregroundStyle(.secondary) }
            ForEach(plugin.displays) { display in
                Section(display.name) {
                    LabeledContent("Connection", value: display.isBuiltIn ? String(localized: "Built-in") : String(localized: "External"))
                    LabeledContent("Looks like", value: display.current.resolutionLabel)
                    LabeledContent("Rendering pixels", value: "\(display.current.pixelWidth) × \(display.current.pixelHeight)")
                    LabeledContent("Refresh Rate", value: display.current.refreshLabel)
                    LabeledContent("HiDPI", value: display.current.isHiDPI ? String(localized: "Yes") : String(localized: "No"))
                    DisclosureGroup("Available Modes") {
                        ForEach(display.modes, id: \.self) { mode in
                            Text(verbatim: "\(mode.resolutionLabel) · \(mode.isHiDPI ? "HiDPI" : "1×") · \(mode.refreshLabel)")
                        }
                    }
                }
            }
        }
        .settingsPane()
        .onAppear { plugin.refresh() }
    }
}
