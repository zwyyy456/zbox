import AppKit
import Observation

@MainActor
@Observable
final class AppEnvironment {
    private let applicationCatalog = ApplicationCatalog()
    private let applicationLauncher = ApplicationLauncher()
    private let applicationIconProvider = ApplicationIconProvider()
    private let searchEngine = SearchEngine()
    private let hotkeyRegistrar = GlobalHotkeyRegistrar()
    private let windowController = AccessibilityWindowController()
    private let launchAtLoginController = LaunchAtLoginController()
    private let hotkeyStore: HotkeyConfigurationStore

    private var commandRegistry = CommandRegistry()
    private var applicationURLsByCommandID: [CommandID: URL] = [:]
    private(set) var applications: [ApplicationInfo] = []
    private(set) var targetApplicationPID: pid_t?
    private(set) var selectedCommandID: CommandID?
    private(set) var rootSearchHotkey: HotkeyPreset
    private(set) var commandHotkeys: [CommandID: HotkeyPreset]
    private(set) var isLaunchAtLoginEnabled = false
    var searchQuery = "" {
        didSet {
            if searchQuery != oldValue {
                selectedCommandID = nil
            }
        }
    }
    var statusMessage = "Ready"

    var searchResults: [SearchMatch] {
        searchEngine.search(
            query: searchQuery,
            in: commandRegistry.descriptors,
            limit: 8
        )
    }

    @ObservationIgnored
    private lazy var searchPanelController = SearchPanelController(environment: self)
    @ObservationIgnored
    private var launchTask: Task<Void, Never>?
    private var hasStarted = false

    init(defaults: UserDefaults = .standard) {
        let hotkeyStore = HotkeyConfigurationStore(defaults: defaults)
        self.hotkeyStore = hotkeyStore
        rootSearchHotkey = hotkeyStore.rootSearchPreset()
        commandHotkeys = Dictionary(
            uniqueKeysWithValues: WindowCommands.shortcutTargets.map { target in
                (target.id, hotkeyStore.commandPreset(for: target.id))
            }
        )
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        reloadApplications()
        isLaunchAtLoginEnabled = launchAtLoginController.isEnabled

        do {
            try applyHotkeyRegistrations()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func stop() {
        launchTask?.cancel()
        hotkeyRegistrar.unregisterAll()
    }

    func toggleRootSearch() {
        if searchPanelController.isVisible {
            searchPanelController.hide()
            return
        }

        targetApplicationPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        searchQuery = ""
        selectedCommandID = nil
        searchPanelController.show()
    }

    func hideRootSearch() {
        searchPanelController.hide()
    }

    func reloadApplications() {
        applications = applicationCatalog.loadApplications()
        let registry = CommandRegistry()
        var applicationURLs: [CommandID: URL] = [:]

        do {
            for application in applications {
                try ApplicationCommands.register(
                    application,
                    in: registry,
                    launcher: applicationLauncher
                )
                applicationURLs[ApplicationCommands.id(for: application)] = application.url
            }
            try WindowCommands.registerAll(in: registry, controller: windowController)
            commandRegistry = registry
            applicationURLsByCommandID = applicationURLs
            statusMessage = "Loaded \(applications.count) applications"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func select(_ commandID: CommandID) {
        selectedCommandID = commandID
    }

    func isSelected(_ commandID: CommandID) -> Bool {
        selectedCommandID == commandID
            || (selectedCommandID == nil && searchResults.first?.id == commandID)
    }

    func moveSelection(by offset: Int) {
        let results = searchResults
        guard !results.isEmpty else {
            selectedCommandID = nil
            return
        }

        let currentIndex = selectedCommandID
            .flatMap { selectedID in results.firstIndex { $0.id == selectedID } }
            ?? 0
        let nextIndex = min(max(currentIndex + offset, 0), results.count - 1)
        selectedCommandID = results[nextIndex].id
    }

    func executeSelectedCommand() {
        let results = searchResults
        guard let commandID = selectedCommandID ?? results.first?.id,
              let descriptor = results.first(where: { $0.id == commandID })?.descriptor else {
            return
        }

        let context = CommandContext(
            source: .rootSearch,
            frontmostApplicationPID: targetApplicationPID
        )
        execute(
            commandID,
            descriptor: descriptor,
            context: context,
            hidePanelOnSuccess: true
        )
    }

    private func execute(
        _ commandID: CommandID,
        descriptor: CommandDescriptor,
        context: CommandContext,
        hidePanelOnSuccess: Bool
    ) {
        let registry = commandRegistry
        launchTask?.cancel()
        launchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await registry.execute(commandID, context: context)
                statusMessage = "Ran \(descriptor.title)"
                if hidePanelOnSuccess {
                    hideRootSearch()
                }
            } catch is CancellationError {
                return
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    func applicationIcon(for commandID: CommandID) -> NSImage? {
        guard let applicationURL = applicationURLsByCommandID[commandID] else {
            return nil
        }
        return applicationIconProvider.icon(for: applicationURL)
    }

    func systemImage(for commandID: CommandID) -> String? {
        WindowCommands.systemImage(for: commandID)
    }

    func commandHotkey(for commandID: CommandID) -> HotkeyPreset {
        commandHotkeys[commandID] ?? .none
    }

    func setRootSearchHotkey(_ preset: HotkeyPreset) {
        let previous = rootSearchHotkey
        rootSearchHotkey = preset

        do {
            try applyHotkeyRegistrations()
            hotkeyStore.setRootSearchPreset(preset)
            statusMessage = "Root Search shortcut updated"
        } catch {
            rootSearchHotkey = previous
            try? applyHotkeyRegistrations()
            statusMessage = error.localizedDescription
        }
    }

    func setCommandHotkey(_ preset: HotkeyPreset, for commandID: CommandID) {
        let previous = commandHotkeys[commandID] ?? .none
        commandHotkeys[commandID] = preset

        do {
            try applyHotkeyRegistrations()
            hotkeyStore.setCommandPreset(preset, for: commandID)
            statusMessage = "Command shortcut updated"
        } catch {
            commandHotkeys[commandID] = previous
            try? applyHotkeyRegistrations()
            statusMessage = error.localizedDescription
        }
    }

    func setLaunchAtLoginEnabled(_ isEnabled: Bool) {
        do {
            try launchAtLoginController.setEnabled(isEnabled)
            isLaunchAtLoginEnabled = launchAtLoginController.isEnabled
            statusMessage = isEnabled ? "Launch at Login enabled" : "Launch at Login disabled"
        } catch {
            isLaunchAtLoginEnabled = launchAtLoginController.isEnabled
            statusMessage = error.localizedDescription
        }
    }

    func requestAccessibilityPermission() {
        windowController.requestPermission()
    }

    func openAccessibilitySettings() {
        windowController.openSystemSettings()
    }

    private func applyHotkeyRegistrations() throws {
        let assignments = [
            HotkeyAssignment(owner: "Root Search", preset: rootSearchHotkey),
        ] + WindowCommands.shortcutTargets.map { target in
            HotkeyAssignment(owner: target.title, preset: commandHotkey(for: target.id))
        }
        try HotkeyValidator.validate(assignments)

        hotkeyRegistrar.unregisterAll()
        do {
            if let hotkey = rootSearchHotkey.hotkey {
                try hotkeyRegistrar.register(
                    id: "root-search",
                    hotkey: hotkey,
                    label: rootSearchHotkey.label
                ) { [weak self] in
                    self?.toggleRootSearch()
                }
            }

            for target in WindowCommands.shortcutTargets {
                let preset = commandHotkey(for: target.id)
                guard let hotkey = preset.hotkey else { continue }
                try hotkeyRegistrar.register(
                    id: target.id.rawValue,
                    hotkey: hotkey,
                    label: preset.label
                ) { [weak self] in
                    self?.executeDirectCommand(target.id)
                }
            }
        } catch {
            hotkeyRegistrar.unregisterAll()
            throw error
        }
    }

    private func executeDirectCommand(_ commandID: CommandID) {
        guard let descriptor = commandRegistry.descriptors.first(where: { $0.id == commandID }) else {
            return
        }
        let context = CommandContext(
            source: .directHotkey,
            frontmostApplicationPID: NSWorkspace.shared.frontmostApplication?.processIdentifier
        )
        execute(
            commandID,
            descriptor: descriptor,
            context: context,
            hidePanelOnSuccess: false
        )
    }
}
