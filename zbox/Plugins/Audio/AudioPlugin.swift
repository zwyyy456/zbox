import SwiftUI
import CoreAudio

@MainActor @Observable
final class AudioPlugin {
    enum Action: String, CaseIterable {
        case open, output, input, louder, quieter, muteOutput, muteInput
        var id: CommandID { CommandID("audio.\(rawValue)") }
        var title: String {
            switch self {
            case .open: String(localized: "Audio Controls")
            case .output: String(localized: "Select Output Device")
            case .input: String(localized: "Select Input Device")
            case .louder: String(localized: "Increase Output Volume")
            case .quieter: String(localized: "Decrease Output Volume")
            case .muteOutput: String(localized: "Toggle Output Mute")
            case .muteInput: String(localized: "Toggle Input Mute")
            }
        }
    }
    static var shortcutTargets: [CommandShortcutTarget] {
        Action.allCases.map { CommandShortcutTarget(id: $0.id, title: $0.title) }
    }
    private let defaults: UserDefaults
    private let controller = AudioController()
    private(set) var isEnabled: Bool
    private(set) var states: [AudioDirection: AudioChannelState] = [:]
    var statusMessage: String?
    var direction: AudioDirection?
    var query = ""
    @ObservationIgnored private var panel: AudioPanel?

    init(defaults: UserDefaults) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: "audio.enabled")
    }

    func start() { if isEnabled { refresh() } }
    func stop() { controller.stopObserving(); dismiss(); states = [:] }
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: "audio.enabled")
        if enabled { start() } else { stop() }
    }
    func refresh() {
        guard isEnabled else { return }
        do {
            var next: [AudioDirection: AudioChannelState] = [:]
            for direction in AudioDirection.allCases { next[direction] = try controller.snapshot(direction) }
            states = next
            try controller.observe(states) { [weak self] in self?.refresh() }
            statusMessage = nil
        } catch { states = [:]; statusMessage = error.localizedDescription }
    }
    func perform(_ operation: () throws -> Void) {
        do { try operation(); refresh() }
        catch { refresh(); statusMessage = error.localizedDescription }
    }
    func select(_ device: AudioDeviceID, direction: AudioDirection) {
        perform { try controller.select(device, direction: direction) }
    }
    func volume(_ value: Float32, direction: AudioDirection, device: AudioDeviceID) {
        perform { try controller.setVolume(value, direction: direction, device: device) }
    }
    func mute(_ direction: AudioDirection) { perform { try controller.toggleMute(direction) } }
    func dismiss() { panel?.orderOut(nil); query = "" }

    func register(in registry: CommandRegistry, openSettings: @escaping @MainActor () throws -> Void) throws {
        for action in Action.allCases {
            try registry.register(CommandDescriptor(id: action.id, title: action.title, subtitle: String(localized: "Audio"),
                keywords: ["audio", "sound", "volume", "microphone", "音频", "音量", "静音", "设备", "麦克风"])) { [weak self] _ in
                guard let self else { return }
                guard isEnabled else { try openSettings(); return }
                switch action {
                case .open, .output, .input:
                    show(direction: action == .open ? nil : action == .output ? .output : .input)
                case .muteOutput, .muteInput:
                    try controller.toggleMute(action == .muteOutput ? .output : .input)
                    refresh()
                case .louder, .quieter:
                    let state = try controller.snapshot(.output)
                    guard let volume = state.volume else { throw AudioControlError.unsupported }
                    try controller.setVolume(volume + (action == .louder ? 0.05 : -0.05), direction: .output, device: state.selected)
                    refresh()
                }
            }
        }
    }
    private func show(direction: AudioDirection?) {
        self.direction = direction
        query = ""
        refresh()
        if panel == nil {
            let panel = AudioPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 410),
                                   styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = String(localized: "Audio")
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isReleasedWhenClosed = false
            panel.onDismiss = { [weak self] in self?.dismiss() }
            panel.contentView = NSHostingView(rootView: AudioControlView(plugin: self))
            panel.center()
            self.panel = panel
        }
        panel?.makeKeyAndOrderFront(nil)
    }
}

private final class AudioPanel: NSPanel {
    var onDismiss: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func close() { onDismiss?(); super.close() }
    override func cancelOperation(_ sender: Any?) { onDismiss?() }
}

struct AudioControlView: View {
    @Bindable var plugin: AudioPlugin
    @State private var selectedDevice: AudioDeviceID?
    @FocusState private var searchFocused: Bool
    var body: some View {
        VStack {
            if let direction = plugin.direction {
                TextField("Search Audio Devices", text: $plugin.query)
                    .textFieldStyle(.roundedBorder).focused($searchFocused)
                let devices = (plugin.states[direction]?.devices ?? []).filter {
                    plugin.query.isEmpty || $0.name.localizedStandardContains(plugin.query)
                }
                List(devices, selection: $selectedDevice) { device in
                    HStack {
                        Text(device.name)
                        Spacer()
                        if plugin.states[direction]?.selected == device.id {
                            Image(systemName: "checkmark").accessibilityLabel(Text("Current Device"))
                        }
                    }.tag(device.id)
                }
                Button("Use Device") {
                    if let id = selectedDevice ?? devices.first?.id { plugin.select(id, direction: direction) }
                }.keyboardShortcut(.defaultAction).disabled(devices.isEmpty)
            } else {
                Form {
                    ForEach(AudioDirection.allCases) { direction in
                        let state = plugin.states[direction] ?? AudioChannelState()
                        Section(direction.title) {
                            Picker("Device", selection: Binding(get: { state.selected }, set: { plugin.select($0, direction: direction) })) {
                                if state.selected == 0 { Text("No Device").tag(AudioDeviceID(0)) }
                                ForEach(state.devices) { Text($0.name).tag($0.id) }
                            }
                            if let volume = state.volume {
                                HStack {
                                    Slider(value: Binding(get: { volume }, set: { plugin.volume($0, direction: direction, device: state.selected) }), in: 0...1)
                                        .accessibilityLabel(Text("\(direction.title) Volume"))
                                    Text("\(Int(volume * 100))%").monospacedDigit().frame(width: 45, alignment: .trailing)
                                }
                            } else { Text("Volume control is not supported.").foregroundStyle(.secondary) }
                            if let muted = state.muted {
                                Toggle("Mute", isOn: Binding(get: { muted }, set: { _ in plugin.mute(direction) }))
                            } else { Text("Mute is not supported.").foregroundStyle(.secondary) }
                        }
                    }
                }.formStyle(.grouped)
            }
            if let message = plugin.statusMessage { SettingsErrorView(message: message) }
        }.padding().onAppear { searchFocused = true }
        .onChange(of: plugin.direction) { selectedDevice = nil; searchFocused = true }
        .onChange(of: plugin.query) { selectedDevice = nil }
    }
}

struct AudioSettingsView: View {
    let environment: AppEnvironment
    var body: some View {
        Form {
            Toggle("Enable Audio Controls", isOn: Binding(get: { environment.audioPlugin.isEnabled }, set: environment.setAudioEnabled))
            Text("Control default audio devices. Available volume and mute controls depend on the device.").foregroundStyle(.secondary)
            if let message = environment.audioPlugin.statusMessage { SettingsErrorView(message: message) }
            if let message = environment.shortcutRegistrationError { SettingsErrorView(message: message) }
        }.settingsPane()
    }
}
