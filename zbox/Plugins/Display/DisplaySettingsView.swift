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
            if plugin.change.pending != nil {
                Section("Keep these display settings?") {
                    Text("Reverting in \(plugin.change.remainingSeconds) seconds.")
                    HStack {
                        Button("Keep Settings") { plugin.change.keep(); plugin.refresh() }
                            .disabled(plugin.change.recoveryFailed)
                        Button("Revert Settings") { plugin.change.revert(); plugin.refresh() }
                    }
                }
            }
            if let error = plugin.change.errorMessage { SettingsErrorView(message: error) }
            if plugin.displays.isEmpty { Text("No displays available.").foregroundStyle(.secondary) }
            ForEach(plugin.displays) { display in
                Section(display.name) {
                    LabeledContent("Connection", value: display.isBuiltIn ? String(localized: "Built-in") : String(localized: "External"))
                    LabeledContent("Looks like", value: display.current.resolutionLabel)
                    LabeledContent("Rendering pixels", value: "\(display.current.pixelWidth) × \(display.current.pixelHeight)")
                    LabeledContent("Refresh Rate", value: display.current.refreshLabel)
                    LabeledContent("HiDPI", value: display.current.isHiDPI ? String(localized: "Yes") : String(localized: "No"))
                    DisplayModePicker(display: display) { mode in
                        plugin.apply([DisplaySelection(displayID: display.id, displayName: display.name, mode: mode)])
                    }
                    .disabled(!plugin.isEnabled || plugin.change.pending != nil)
                }
            }
        }
        .settingsPane()
        .onAppear { plugin.refresh() }
    }
}

private struct DisplayModePicker: View {
    let display: DisplayInfo
    let apply: (DisplayModeSpec) -> Void
    @State private var selection: DisplayModeSpec?

    private var modes: [DisplayModeSpec] { display.modes }

    var body: some View {
        Picker("Display Mode", selection: $selection) {
            Text("Choose a mode…").tag(DisplayModeSpec?.none)
            ForEach(modes, id: \.self) { mode in
                Text(verbatim: "\(mode.resolutionLabel) · \(mode.isHiDPI ? "HiDPI" : "1×") · \(mode.refreshLabel)")
                    .tag(Optional(mode))
            }
        }
        Button("Apply Mode") {
            if let selection { apply(selection) }
        }
        .disabled(selection == nil || selection == display.current || !modes.contains(where: { $0 == selection }))
        .onAppear { selection = display.current }
        .onChange(of: display.current) { _, current in selection = current }
    }
}
