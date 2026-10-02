import SwiftUI

struct DisplaySettingsView: View {
    let environment: AppEnvironment
    @State private var editingPreset: DisplayPreset?
    @State private var configuringHiDPI: DisplayInfo?
    @State private var removingHiDPI: DisplayHiDPIInstallation?

    var body: some View {
        let plugin = environment.displayPlugin
        Form {
            Section {
                Toggle("Enable Display", isOn: Binding(get: { plugin.isEnabled }, set: environment.setDisplayEnabled))
                    .disabled(plugin.hiDPI.isBusy)
                Button("Refresh Displays", action: plugin.refresh)
                if let message = plugin.statusMessage { Text(message).font(.caption) }
            }
            Section("Display Presets") {
                Button("Save Current Display Preset") { editingPreset = plugin.snapshot() }
                    .disabled(!plugin.isEnabled || plugin.displays.isEmpty || plugin.change.pending != nil)
                if let error = plugin.presets.errorMessage { SettingsErrorView(message: error) }
                ForEach(plugin.presets.presets) { preset in
                    HStack {
                        Text(preset.name).lineLimit(1).help(preset.name)
                        Spacer()
                        Button("Apply") { environment.applyDisplayPreset(preset) }
                            .disabled(!plugin.isEnabled || plugin.change.pending != nil || plugin.hiDPI.isBusy)
                        Menu {
                            Button("Rename") { plugin.statusMessage = nil; editingPreset = preset }
                            Button("Delete", role: .destructive) { environment.deleteDisplayPreset(preset) }
                        } label: { Image(systemName: "ellipsis") }
                        .menuStyle(.borderlessButton).fixedSize()
                        .accessibilityLabel("Display Preset Actions")
                    }
                }
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
                    .disabled(!plugin.isEnabled || plugin.change.pending != nil || plugin.hiDPI.isBusy)
                    if !display.isBuiltIn {
                        Button("Configure Additional HiDPI Modes…") { configuringHiDPI = display }
                            .disabled(!plugin.isEnabled || plugin.change.pending != nil || plugin.hiDPI.isBusy || plugin.hiDPI.loadError != nil)
                    }
                }
            }
            Section("Additional HiDPI") {
                Text("Native scaling uses a system display override. Installation requires administrator approval and a restart; available modes still depend on macOS and the display connection.")
                    .font(.caption).foregroundStyle(.secondary)
                if plugin.hiDPI.isBusy { ProgressView("Updating display configuration…") }
                if let message = plugin.hiDPI.loadError ?? plugin.hiDPI.statusMessage { Text(message).font(.caption) }
                ForEach(plugin.hiDPI.installations) { installation in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(installation.displayName)
                        let matches = plugin.displays.filter { $0.vendor == installation.vendor && $0.product == installation.product }
                        if let display = matches.first, matches.count == 1 {
                            Text("Additional available HiDPI modes since installation: \(installation.additionalModes(on: display))")
                                .font(.caption)
                        }
                        Text("An installation record does not confirm that macOS enabled the requested modes.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Remove zbox Override…", role: .destructive) { removingHiDPI = installation }
                            .disabled(plugin.hiDPI.isBusy || plugin.change.pending != nil)
                    }
                }
            }
        }
        .settingsPane()
        .onAppear { plugin.refresh() }
        .sheet(item: $configuringHiDPI) { display in
            DisplayHiDPIEditor(display: display, manager: plugin.hiDPI)
        }
        .confirmationDialog("Remove this zbox display override?", isPresented: Binding(
            get: { removingHiDPI != nil }, set: { if !$0 { removingHiDPI = nil } })) {
            if let installation = removingHiDPI {
                Button("Remove Override", role: .destructive) {
                    Task { await plugin.hiDPI.remove(installation) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only the unchanged configuration installed by zbox will be removed. Restart macOS afterward.")
        }
        .sheet(item: $editingPreset) { preset in
            DisplayPresetEditor(preset: preset, errorMessage: plugin.statusMessage, save: environment.saveDisplayPreset)
        }
    }
}

private struct DisplayModePicker: View {
    let display: DisplayInfo
    let apply: (DisplayModeSpec) -> Void
    @State private var selection: DisplayModeSpec?

    private var modes: [DisplayModeSpec] { display.modes }

    var body: some View {
        Picker("Resolution", selection: Binding(get: { selection?.resolution }, set: { resolution in
            selection = modes.first { $0.resolution == resolution && $0.refreshMillihertz == selection?.refreshMillihertz }
                ?? modes.first { $0.resolution == resolution }
        })) {
            Text("Choose a mode…").tag(DisplayModeSpec?.none)
            ForEach(modes.reduce(into: [DisplayModeSpec]()) { result, mode in
                if !result.contains(mode.resolution) { result.append(mode.resolution) }
            }, id: \.self) { mode in
                Text(verbatim: "\(mode.resolutionLabel) · \(mode.isHiDPI ? "HiDPI" : "1×")")
                    .tag(Optional(mode))
            }
        }
        Picker("Refresh Rate", selection: $selection) {
            Text("Choose a mode…").tag(DisplayModeSpec?.none)
            ForEach(modes.filter { $0.resolution == selection?.resolution }, id: \.self) { mode in
                Text(mode.refreshLabel).tag(Optional(mode))
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

private struct DisplayPresetEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var preset: DisplayPreset
    let errorMessage: String?
    let save: (DisplayPreset) -> Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Display Preset").font(.headline)
            TextField("Name", text: $preset.name)
            if let errorMessage { SettingsErrorView(message: errorMessage) }
            ForEach(preset.selections, id: \.displayID) { selection in
                LabeledContent(selection.displayName, value: "\(selection.mode.resolutionLabel) · \(selection.mode.refreshLabel)")
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save") {
                    preset.name = preset.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if save(preset) { dismiss() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(preset.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || preset.selections.isEmpty)
            }
        }
        .padding(20).frame(width: 500)
    }
}
