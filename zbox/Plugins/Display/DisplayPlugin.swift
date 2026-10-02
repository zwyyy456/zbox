import AppKit
import Observation

@MainActor
@Observable
final class DisplayPlugin {
    static let manageCommandID = CommandID("display.manage")
    private let defaults: UserDefaults
    private let controller = DisplayController()
    let change = DisplayChange(controller: DisplayController())
    let presets: DisplayPresetStore
    let hiDPI: DisplayHiDPIManager
    private(set) var isEnabled: Bool
    private(set) var displays: [DisplayInfo] = []
    var statusMessage: String?
    @ObservationIgnored private var screenObserver: NSObjectProtocol?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        presets = DisplayPresetStore(defaults: defaults)
        hiDPI = DisplayHiDPIManager(defaults: defaults)
        isEnabled = defaults.bool(forKey: "display.enabled")
    }

    var shortcutTargets: [CommandShortcutTarget] {
        presets.presets.map { CommandShortcutTarget(id: $0.commandID, title: String(localized: "Apply Display Preset: \($0.name)")) }
    }

    func snapshot() -> DisplayPreset {
        refresh()
        return DisplayPreset(name: "", selections: displays.map {
            DisplaySelection(displayID: $0.id, displayName: $0.name, mode: $0.current)
        })
    }

    func start() {
        refresh()
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refresh() }
            }
    }

    func stop() {
        change.revert()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
    }

    func setEnabled(_ enabled: Bool) {
        guard !hiDPI.isBusy else { return }
        if !enabled {
            change.revert()
            guard change.pending == nil else { return }
        }
        isEnabled = enabled
        defaults.set(enabled, forKey: "display.enabled")
        if enabled { start() } else { stop() }
    }

    func apply(_ selections: [DisplaySelection]) {
        guard !hiDPI.isBusy else { return }
        guard isEnabled else { statusMessage = DisplayError.disabled.localizedDescription; return }
        do { try change.begin(selections); statusMessage = nil }
        catch { statusMessage = error.localizedDescription }
        refresh()
    }

    func refresh() {
        displays = controller.read()
        if let pending = change.pending, !change.recoveryFailed,
           !pending.requested.allSatisfy({ selection in
               let matches = displays.filter { $0.id == selection.displayID }
               return matches.count == 1 && matches.first?.current == selection.mode
           }) {
            change.revert()
            displays = controller.read()
            statusMessage = String(localized: "The display configuration changed during confirmation. Restoration was requested.")
        }
    }

    func register(in registry: CommandRegistry, openSettings: @escaping @MainActor () throws -> Void) throws {
        for preset in presets.presets {
            try registry.register(CommandDescriptor(id: preset.commandID,
                title: String(localized: "Apply Display Preset: \(preset.name)"),
                subtitle: preset.selections.map(\.displayName).joined(separator: ", "),
                keywords: ["display", "preset", "显示器", "预设", preset.name])) { [weak self] _ in
                try openSettings()
                guard let self, isEnabled, !hiDPI.isBusy else { return }
                try change.begin(preset.selections)
                refresh()
            }
        }
        try registry.register(CommandDescriptor(id: Self.manageCommandID, title: String(localized: "Manage Displays"),
            subtitle: nil, keywords: ["display", "resolution", "HiDPI", "显示器", "分辨率"])) { _ in try openSettings() }
    }
}
