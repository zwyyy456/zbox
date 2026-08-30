import AppKit
import Observation

@MainActor
@Observable
final class AppEnvironment {
    private enum Key {
        static let windowManagementEnabled = "window-management.enabled"
        static let showApplicationPaths = "search.show-application-paths"
    }

    private let applicationCatalog = ApplicationCatalog()
    private let applicationLauncher = ApplicationLauncher()
    private let applicationIconProvider = ApplicationIconProvider()
    private let searchEngine = SearchEngine()
    private let hotkeyRegistrar: any HotkeyRegistering
    private let accessibilityAuthorization: AccessibilityAuthorization
    private let windowController: AccessibilityWindowController
    private let settingsWindowOpener = SettingsWindowOpener()
    private let launchAtLoginController = LaunchAtLoginController()
    private let hotkeyStore: HotkeyConfigurationStore
    private let defaults: UserDefaults

    @ObservationIgnored
    let textLookupPlugin: TextLookupPlugin

    private var commandRegistry = CommandRegistry()
    private var applicationURLsByCommandID: [CommandID: URL] = [:]
    private(set) var applications: [ApplicationInfo] = []
    private(set) var targetApplicationPID: pid_t?
    private(set) var selectedCommandID: CommandID?
    private(set) var rootSearchHotkey: Hotkey
    private(set) var commandHotkeys: [CommandID: Hotkey]
    private(set) var rootSearchHotkeyError: String?
    private(set) var commandHotkeyErrors: [CommandID: String] = [:]
    private(set) var isLaunchAtLoginEnabled = false
    private(set) var isWindowManagementEnabled: Bool
    private(set) var isAccessibilityTrusted: Bool
    private(set) var showsApplicationPathsInSearchResults: Bool
    private(set) var commandFeedback: CommandFeedback?
    var selectedSettingsTab: SettingsTab = .general
    var searchQuery = "" {
        didSet {
            if searchQuery != oldValue {
                selectedCommandID = nil
            }
        }
    }
    var statusMessage = String(localized: "Ready")

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
    private lazy var commandFeedbackPanelController = CommandFeedbackPanelController(
        onRecovery: { [weak self] action in self?.performCommandRecovery(action) }
    )
    @ObservationIgnored
    private var launchTask: Task<Void, Never>?
    private var commandExecutionID: UUID?
    private var rootSearchSessionID: UUID?
    private var hasStarted = false
    private var isRecordingShortcut = false

    init(
        defaults: UserDefaults = .standard,
        hotkeyRegistrar: any HotkeyRegistering = GlobalHotkeyRegistrar()
    ) {
        let accessibilityAuthorization = AccessibilityAuthorization()
        let hotkeyStore = HotkeyConfigurationStore(defaults: defaults)
        let textLookupSettings = TextLookupSettingsStore(defaults: defaults)
        let textLookupPlugin = TextLookupPlugin(
            settings: textLookupSettings,
            hotkeyRegistrar: hotkeyRegistrar,
            isAccessibilityTrusted: { accessibilityAuthorization.isTrusted }
        )

        self.hotkeyRegistrar = hotkeyRegistrar
        self.accessibilityAuthorization = accessibilityAuthorization
        windowController = AccessibilityWindowController(authorization: accessibilityAuthorization)
        self.hotkeyStore = hotkeyStore
        self.defaults = defaults
        self.textLookupPlugin = textLookupPlugin
        rootSearchHotkey = hotkeyStore.rootSearchHotkey()
        isWindowManagementEnabled = defaults.bool(forKey: Key.windowManagementEnabled)
        isAccessibilityTrusted = accessibilityAuthorization.isTrusted
        showsApplicationPathsInSearchResults = defaults.bool(forKey: Key.showApplicationPaths)
        commandHotkeys = hotkeyStore.commandHotkeys(
            for: WindowCommands.shortcutTargets.map(\.id)
        )
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        reconcileAccessibilityDependentFeatures()
        reloadApplications()
        isLaunchAtLoginEnabled = launchAtLoginController.isEnabled

        do {
            try applyHotkeyRegistrations()
        } catch {
            statusMessage = error.localizedDescription
        }

        if textLookupPlugin.settings.isEnabled, isAccessibilityTrusted {
            textLookupPlugin.start()
        }
    }

    func stop() {
        launchTask?.cancel()
        commandExecutionID = nil
        rootSearchSessionID = nil
        commandFeedbackPanelController.hide()
        textLookupPlugin.stop()
        hotkeyRegistrar.unregisterAll()
    }

    func toggleRootSearch() {
        if searchPanelController.isVisible {
            hideRootSearch()
            return
        }

        rootSearchSessionID = UUID()
        targetApplicationPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        searchQuery = ""
        selectedCommandID = nil
        commandFeedback = nil
        commandFeedbackPanelController.hide()
        searchPanelController.show()
    }

    func hideRootSearch() {
        rootSearchSessionID = nil
        searchPanelController.hide()
    }

    func reloadApplications() {
        applications = applicationCatalog.loadApplications()
        let registry = CommandRegistry()
        var applicationURLs: [CommandID: URL] = [:]

        do {
            try WindowCommands.registerAll(
                in: registry,
                controller: windowController,
                isEnabled: { [weak self] in self?.isWindowManagementEnabled == true }
            )
            try SettingsCommands.register(in: registry) { [weak self] in
                try self?.openSettings(tab: .general)
            }
            for application in applications {
                try ApplicationCommands.register(
                    application,
                    in: registry,
                    launcher: applicationLauncher
                )
                applicationURLs[ApplicationCommands.id(for: application)] = application.url
            }
            commandRegistry = registry
            applicationURLsByCommandID = applicationURLs
            statusMessage = String(localized: "Loaded \(applications.count) applications")
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
        let executionID = UUID()
        let expectedRootSearchSessionID = hidePanelOnSuccess ? rootSearchSessionID : nil
        launchTask?.cancel()
        if context.source == .directHotkey {
            commandFeedbackPanelController.hide()
        }
        commandExecutionID = executionID
        launchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await registry.execute(commandID, context: context)
                guard isCurrentExecution(
                    executionID,
                    expectedRootSearchSessionID: expectedRootSearchSessionID
                ) else { return }
                if hidePanelOnSuccess {
                    commandFeedback = .success(String(localized: "Ran \(descriptor.title)"))
                    hideRootSearch()
                }
            } catch is CancellationError {
                return
            } catch {
                guard isCurrentExecution(
                    executionID,
                    expectedRootSearchSessionID: expectedRootSearchSessionID
                ) else { return }
                if error as? AccessibilityWindowError == .permissionRequired {
                    reconcileAccessibilityDependentFeatures()
                }
                let feedback = CommandFeedbackMapper.failure(for: error)
                if context.source == .rootSearch {
                    commandFeedback = feedback
                } else {
                    commandFeedbackPanelController.show(feedback)
                }
            }
        }
    }

    private func isCurrentExecution(
        _ executionID: UUID,
        expectedRootSearchSessionID: UUID?
    ) -> Bool {
        guard !Task.isCancelled, commandExecutionID == executionID else { return false }
        return expectedRootSearchSessionID == nil
            || rootSearchSessionID == expectedRootSearchSessionID
    }

    func applicationIcon(for commandID: CommandID) -> NSImage? {
        guard let applicationURL = applicationURLsByCommandID[commandID] else {
            return nil
        }
        return applicationIconProvider.icon(for: applicationURL)
    }

    func subtitle(for descriptor: CommandDescriptor) -> String? {
        guard applicationURLsByCommandID[descriptor.id] != nil else {
            return descriptor.subtitle
        }
        return showsApplicationPathsInSearchResults ? descriptor.subtitle : nil
    }

    func systemImage(for commandID: CommandID) -> String? {
        WindowCommands.systemImage(for: commandID)
            ?? SettingsCommands.systemImage(for: commandID)
    }

    func commandHotkey(for commandID: CommandID) -> Hotkey? {
        commandHotkeys[commandID]
    }

    func setRootSearchHotkey(_ hotkey: Hotkey) {
        let previous = rootSearchHotkey
        rootSearchHotkeyError = nil

        do {
            try HotkeyValidator.validateUserShortcut(hotkey)
            rootSearchHotkey = hotkey
            try applyHotkeyRegistrations()
            hotkeyStore.setRootSearchHotkey(hotkey)
            statusMessage = String(localized: "Root Search shortcut updated")
        } catch {
            rootSearchHotkey = previous
            rootSearchHotkeyError = error.localizedDescription
            statusMessage = error.localizedDescription
        }
    }

    func reportInvalidRootSearchHotkey(_ message: String) {
        rootSearchHotkeyError = message
        statusMessage = message
    }

    func setCommandHotkey(_ hotkey: Hotkey?, for commandID: CommandID) {
        let previous = commandHotkeys[commandID]
        commandHotkeyErrors[commandID] = nil

        do {
            if let hotkey {
                try HotkeyValidator.validateUserShortcut(hotkey)
                commandHotkeys[commandID] = hotkey
            } else {
                commandHotkeys[commandID] = nil
            }
            try applyHotkeyRegistrations()
            hotkeyStore.setCommandHotkey(hotkey, for: commandID)
            statusMessage = String(localized: "Command shortcut updated")
        } catch {
            commandHotkeys[commandID] = previous
            commandHotkeyErrors[commandID] = error.localizedDescription
            statusMessage = error.localizedDescription
        }
    }

    func reportInvalidCommandHotkey(_ message: String, for commandID: CommandID) {
        commandHotkeyErrors[commandID] = message
        statusMessage = message
    }

    func setShortcutRecordingActive(_ isActive: Bool) {
        guard isActive != isRecordingShortcut else { return }
        isRecordingShortcut = isActive

        do {
            try hotkeyRegistrar.setSuspended(isActive)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func setLaunchAtLoginEnabled(_ isEnabled: Bool) {
        do {
            try launchAtLoginController.setEnabled(isEnabled)
            isLaunchAtLoginEnabled = launchAtLoginController.isEnabled
            statusMessage = isEnabled
                ? String(localized: "Launch at Login enabled")
                : String(localized: "Launch at Login disabled")
        } catch {
            isLaunchAtLoginEnabled = launchAtLoginController.isEnabled
            statusMessage = error.localizedDescription
        }
    }

    func setShowsApplicationPathsInSearchResults(_ isEnabled: Bool) {
        showsApplicationPathsInSearchResults = isEnabled
        defaults.set(isEnabled, forKey: Key.showApplicationPaths)
        statusMessage = isEnabled
            ? String(localized: "Application paths shown in search results")
            : String(localized: "Application paths hidden in search results")
    }

    func setWindowManagementEnabled(_ isEnabled: Bool) {
        refreshAccessibilityState()

        guard isEnabled else {
            disableWindowManagement()
            statusMessage = String(localized: "Window Management disabled")
            return
        }
        guard isAccessibilityTrusted else {
            statusMessage = String(localized: "Accessibility permission is required to enable Window Management.")
            return
        }
        guard !isWindowManagementEnabled else { return }

        isWindowManagementEnabled = true
        do {
            try applyHotkeyRegistrations()
            defaults.set(true, forKey: Key.windowManagementEnabled)
            statusMessage = String(localized: "Window Management enabled")
        } catch {
            isWindowManagementEnabled = false
            statusMessage = error.localizedDescription
        }
    }

    func setTextLookupEnabled(_ isEnabled: Bool) {
        do {
            if isEnabled {
                refreshAccessibilityState()
                guard isAccessibilityTrusted else {
                    statusMessage = String(localized: "Accessibility permission is required to enable Text Lookup.")
                    return
                }
                try validateHotkeyAssignments(
                    textLookupShortcut: textLookupPlugin.settings.shortcut,
                    textLookupEnabled: true
                )
            }
            textLookupPlugin.settings.setEnabled(isEnabled)
            if isEnabled {
                textLookupPlugin.start()
            } else {
                textLookupPlugin.stop()
            }
            statusMessage = textLookupPlugin.statusMessage
                ?? (isEnabled
                    ? String(localized: "Text Lookup enabled")
                    : String(localized: "Text Lookup disabled"))
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func setTextLookupShortcut(_ shortcut: TextLookupShortcutPreset) {
        do {
            try validateHotkeyAssignments(textLookupShortcut: shortcut)
            try textLookupPlugin.setShortcut(shortcut)
            statusMessage = String(localized: "Text Lookup shortcut updated")
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func requestAccessibilityPermission() {
        windowController.requestPermission()
        refreshAccessibilityState()
    }

    func openAccessibilitySettings() {
        windowController.openSystemSettings()
    }

    func performCommandRecovery(_ action: CommandRecoveryAction) {
        switch action {
        case .openAccessibilitySettings:
            openAccessibilitySettings()
        case .openWindowManagementSettings:
            do {
                try openSettings(tab: .windowManagement)
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    func openSettings(tab: SettingsTab) throws {
        selectedSettingsTab = tab
        try settingsWindowOpener.open()
    }

    func reconcileAccessibilityDependentFeatures() {
        refreshAccessibilityState()
        guard !isAccessibilityTrusted else { return }

        let disabledWindowManagement = isWindowManagementEnabled
        let disabledTextLookup = textLookupPlugin.settings.isEnabled
        if disabledWindowManagement {
            disableWindowManagement()
        }
        if disabledTextLookup {
            textLookupPlugin.settings.setEnabled(false)
            textLookupPlugin.stop()
        }
        if disabledWindowManagement || disabledTextLookup {
            statusMessage = String(localized: "Accessibility-dependent features were disabled. Re-enable them after granting permission.")
        }
    }

    private func applyHotkeyRegistrations() throws {
        try validateHotkeyAssignments(textLookupShortcut: textLookupPlugin.settings.shortcut)

        var requests: [HotkeyRegistrationRequest] = []
        requests.append(
            HotkeyRegistrationRequest(
                id: "root-search",
                hotkey: rootSearchHotkey,
                label: HotkeyFormatter.displayName(for: rootSearchHotkey)
            ) { [weak self] in
                self?.toggleRootSearch()
            }
        )

        if isWindowManagementEnabled, accessibilityAuthorization.isTrusted {
            for target in WindowCommands.shortcutTargets {
                guard let hotkey = commandHotkey(for: target.id) else { continue }
                requests.append(
                    HotkeyRegistrationRequest(
                        id: target.id.rawValue,
                        hotkey: hotkey,
                        label: HotkeyFormatter.displayName(for: hotkey)
                    ) { [weak self] in
                        self?.executeDirectCommand(target.id)
                    }
                )
            }
        }

        let coreIDs = Set(["root-search"] + WindowCommands.shortcutTargets.map(\.id.rawValue))
        try hotkeyRegistrar.replace(ids: coreIDs, with: requests)
    }

    private func validateHotkeyAssignments(
        textLookupShortcut: TextLookupShortcutPreset,
        textLookupEnabled: Bool? = nil
    ) throws {
        var assignments = [
            HotkeyAssignment(owner: String(localized: "Root Search"), hotkey: rootSearchHotkey),
        ] + WindowCommands.shortcutTargets.map { target in
            HotkeyAssignment(owner: target.title, hotkey: commandHotkey(for: target.id))
        }
        if textLookupEnabled ?? textLookupPlugin.settings.isEnabled {
            assignments.append(
                HotkeyAssignment(
                    owner: String(localized: "Text Lookup"),
                    hotkey: textLookupShortcut.hotkey
                )
            )
        }
        try HotkeyValidator.validate(assignments)
    }

    private func refreshAccessibilityState() {
        isAccessibilityTrusted = accessibilityAuthorization.isTrusted
    }

    private func disableWindowManagement() {
        isWindowManagementEnabled = false
        defaults.set(false, forKey: Key.windowManagementEnabled)
        for target in WindowCommands.shortcutTargets {
            hotkeyRegistrar.unregister(id: target.id.rawValue)
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
