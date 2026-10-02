import AppKit
import Observation

@MainActor
@Observable
final class AppEnvironment {
    private enum Key {
        static let showApplicationPaths = "search.show-application-paths"
    }

    private let clipboardCoordinator: ClipboardAccessCoordinator
    private let applicationCatalog = ApplicationCatalog()
    private let applicationLauncher = ApplicationLauncher()
    private let applicationIconProvider = ApplicationIconProvider()
    private let searchEngine = SearchEngine()
    private let hotkeyRegistrar: any HotkeyRegistering
    private let accessibilityAuthorization: AccessibilityAuthorization
    private let settingsWindowOpener = SettingsWindowOpener()
    private let launchAtLoginController = LaunchAtLoginController()
    private let hotkeyStore: HotkeyConfigurationStore
    private let defaults: UserDefaults

    @ObservationIgnored
    let textLookupPlugin: TextLookupPlugin
    @ObservationIgnored
    let windowManagementPlugin: WindowManagementPlugin
    @ObservationIgnored
    let clipboardHistoryPlugin: ClipboardHistoryPlugin
    @ObservationIgnored
    let screenshotPlugin: ScreenshotPlugin
    @ObservationIgnored
    let calculatorPlugin = CalculatorPlugin()
    let workspacePlugin: WorkspacePlugin

    private var commandRegistry = CommandRegistry()
    private var applicationURLsByCommandID: [CommandID: URL] = [:]
    private(set) var applications: [ApplicationInfo] = []
    private(set) var targetApplicationPID: pid_t?
    private(set) var selectedCommandID: CommandID?
    private(set) var rootSearchHotkey: Hotkey
    private(set) var commandHotkeys: [CommandID: Hotkey]
    private(set) var rootSearchHotkeyError: String?
    private(set) var commandHotkeyErrors: [CommandID: String] = [:]
    private(set) var applicationReloadError: String?
    private(set) var launchAtLoginError: String?
    private(set) var shortcutRegistrationError: String?
    private(set) var textLookupError: String?
    private(set) var isLaunchAtLoginEnabled = false
    private(set) var isAccessibilityTrusted: Bool
    private(set) var showsApplicationPathsInSearchResults: Bool
    private(set) var commandFeedback: CommandFeedback?
    var selectedSettingsTab: SettingsTab = .general
    var commandShortcutTargets: [CommandShortcutTarget] {
        workspacePlugin.shortcutTargets + ScreenshotPlugin.shortcutTargets + WindowCommands.shortcutTargets + [CommandShortcutTarget(id: ClipboardHistoryPlugin.commandID,
                                                               title: String(localized: "Clipboard History"))]
    }

    var searchQuery = "" {
        didSet {
            if searchQuery != oldValue {
                selectedCommandID = nil
            }
        }
    }
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
        let clipboardCoordinator = ClipboardAccessCoordinator()
        self.clipboardCoordinator = clipboardCoordinator
        let workspacePlugin = WorkspacePlugin(defaults: defaults)
        self.workspacePlugin = workspacePlugin
        screenshotPlugin = ScreenshotPlugin(defaults: defaults, clipboardCoordinator: clipboardCoordinator)
        let accessibilityAuthorization = AccessibilityAuthorization()
        clipboardHistoryPlugin = ClipboardHistoryPlugin(defaults: defaults, coordinator: clipboardCoordinator,
                                                        authorization: accessibilityAuthorization)
        let hotkeyStore = HotkeyConfigurationStore(defaults: defaults)
        let textLookupSettings = TextLookupSettingsStore(defaults: defaults)
        let textLookupPlugin = TextLookupPlugin(
            settings: textLookupSettings,
            clipboardCoordinator: clipboardCoordinator,
            hotkeyRegistrar: hotkeyRegistrar,
            isAccessibilityTrusted: { accessibilityAuthorization.isTrusted }
        )

        self.hotkeyRegistrar = hotkeyRegistrar
        self.accessibilityAuthorization = accessibilityAuthorization
        windowManagementPlugin = WindowManagementPlugin(
            defaults: defaults,
            hotkeyRegistrar: hotkeyRegistrar,
            controller: AccessibilityWindowController(authorization: accessibilityAuthorization),
            isAccessibilityTrusted: { accessibilityAuthorization.isTrusted }
        )
        self.hotkeyStore = hotkeyStore
        self.defaults = defaults
        self.textLookupPlugin = textLookupPlugin
        rootSearchHotkey = hotkeyStore.rootSearchHotkey()
        isAccessibilityTrusted = accessibilityAuthorization.isTrusted
        showsApplicationPathsInSearchResults = defaults.bool(forKey: Key.showApplicationPaths)
        commandHotkeys = hotkeyStore.commandHotkeys(
            for: workspacePlugin.shortcutTargets.map(\.id) + WindowCommands.shortcutTargets.map(\.id) + ScreenshotPlugin.shortcutTargets.map(\.id) + [ClipboardHistoryPlugin.commandID]
        )
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        workspacePlugin.onCompletion = { [weak self] message, permissionLost in
            guard let self else { return }
            if permissionLost { reconcileAccessibilityDependentFeatures() }
            if let message {
                commandFeedbackPanelController.show(CommandFeedback(message: message, recoveryAction: .openWorkspaceSettings))
            }
        }
        reconcileAccessibilityDependentFeatures()
        windowManagementPlugin.start()
        clipboardHistoryPlugin.start()
        reloadApplications()
        isLaunchAtLoginEnabled = launchAtLoginController.isEnabled

        do {
            try applyHotkeyRegistrations()
        } catch {
            shortcutRegistrationError = error.localizedDescription
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
        calculatorPlugin.stop()
        windowManagementPlugin.stop()
        clipboardHistoryPlugin.stop()
        screenshotPlugin.stop()
        workspacePlugin.stop()
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
            try windowManagementPlugin.register(in: registry)
            try SettingsCommands.register(in: registry) { [weak self] in
                try self?.openSettings(tab: .general)
            }
            try calculatorPlugin.register(in: registry)
            try workspacePlugin.register(in: registry) { [weak self] in
                try self?.openSettings(tab: .workspace)
            }
            try screenshotPlugin.register(in: registry) { [weak self] in
                try self?.openSettings(tab: .screenshot)
            }
            try clipboardHistoryPlugin.register(in: registry) { [weak self] in
                try self?.openSettings(tab: .clipboardHistory)
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
            applicationReloadError = nil
        } catch {
            applicationReloadError = error.localizedDescription
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
        guard let commandID = selectedCommandID ?? results.first?.id else {
            return
        }

        let context = CommandContext(
            source: .rootSearch,
            frontmostApplicationPID: targetApplicationPID
        )
        execute(
            commandID,
            context: context,
            hidePanelOnSuccess: true
        )
    }

    private func execute(
        _ commandID: CommandID,
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
        if commandID.rawValue.hasPrefix("workspace.") { return "rectangle.3.group" }
        if ScreenshotPlugin.shortcutTargets.contains(where: { $0.id == commandID }) { return "camera.viewfinder" }
        if commandID == ClipboardHistoryPlugin.commandID { return "clipboard" }
        return WindowCommands.systemImage(for: commandID)
            ?? SettingsCommands.systemImage(for: commandID)
            ?? calculatorPlugin.systemImage(for: commandID)
    }

    func commandHotkey(for commandID: CommandID) -> Hotkey? {
        commandHotkeys[commandID]
    }

    func setRootSearchHotkey(_ hotkey: Hotkey) {
        let previous = rootSearchHotkey
        rootSearchHotkeyError = nil

        do {
            try HotkeyValidator.validateUserShortcut(hotkey)
            // Resume the old registrations before replacing them so failure can roll back.
            if isRecordingShortcut {
                try hotkeyRegistrar.setSuspended(false)
            }
            rootSearchHotkey = hotkey
            try applyHotkeyRegistrations()
            hotkeyStore.setRootSearchHotkey(hotkey)
            shortcutRegistrationError = nil
        } catch {
            rootSearchHotkey = previous
            rootSearchHotkeyError = error.localizedDescription
        }
    }

    func reportInvalidRootSearchHotkey(_ message: String) {
        rootSearchHotkeyError = message
    }

    func setCommandHotkey(_ hotkey: Hotkey?, for commandID: CommandID) {
        let previous = commandHotkeys[commandID]
        commandHotkeyErrors[commandID] = nil

        do {
            if let hotkey {
                try HotkeyValidator.validateUserShortcut(hotkey)
            }
            if isRecordingShortcut {
                try hotkeyRegistrar.setSuspended(false)
            }
            commandHotkeys[commandID] = hotkey
            try applyHotkeyRegistrations()
            hotkeyStore.setCommandHotkey(hotkey, for: commandID)
            shortcutRegistrationError = nil
        } catch {
            commandHotkeys[commandID] = previous
            commandHotkeyErrors[commandID] = error.localizedDescription
        }
    }

    func reportInvalidCommandHotkey(_ message: String, for commandID: CommandID) {
        commandHotkeyErrors[commandID] = message
    }

    func setShortcutRecordingActive(_ isActive: Bool) {
        guard isActive != isRecordingShortcut else { return }
        isRecordingShortcut = isActive

        do {
            try hotkeyRegistrar.setSuspended(isActive)
            shortcutRegistrationError = nil
        } catch {
            shortcutRegistrationError = error.localizedDescription
        }
    }

    func setLaunchAtLoginEnabled(_ isEnabled: Bool) {
        do {
            try launchAtLoginController.setEnabled(isEnabled)
            isLaunchAtLoginEnabled = launchAtLoginController.isEnabled
            launchAtLoginError = nil
        } catch {
            isLaunchAtLoginEnabled = launchAtLoginController.isEnabled
            launchAtLoginError = error.localizedDescription
        }
    }

    func setShowsApplicationPathsInSearchResults(_ isEnabled: Bool) {
        showsApplicationPathsInSearchResults = isEnabled
        defaults.set(isEnabled, forKey: Key.showApplicationPaths)
    }

    func setWindowManagementEnabled(_ isEnabled: Bool) {
        refreshAccessibilityState()
        windowManagementPlugin.setEnabled(isEnabled) {
            try applyHotkeyRegistrations()
        }
    }

    func setWorkspaceEnabled(_ enabled: Bool) {
        refreshAccessibilityState()
        guard !enabled || isAccessibilityTrusted else {
            workspacePlugin.statusMessage = String(localized: "Accessibility permission is required to move windows.")
            return
        }
        workspacePlugin.setEnabled(enabled)
        if !enabled {
            for target in workspacePlugin.shortcutTargets { hotkeyRegistrar.unregister(id: target.id.rawValue) }
            return
        }
        do {
            try applyHotkeyRegistrations()
            workspacePlugin.statusMessage = nil
        } catch {
            workspacePlugin.setEnabled(false)
            workspacePlugin.statusMessage = error.localizedDescription
        }
    }

    func restoreWorkspace(_ layout: WorkspaceLayout) {
        executeDirectCommand(layout.commandID)
    }

    func saveWorkspace(_ layout: WorkspaceLayout) {
        do {
            try workspacePlugin.store.save(layout)
            reloadApplications()
            try applyHotkeyRegistrations()
            workspacePlugin.statusMessage = nil
        } catch { workspacePlugin.statusMessage = error.localizedDescription }
    }

    func deleteWorkspace(_ layout: WorkspaceLayout) {
        do {
            try workspacePlugin.store.delete(layout.id)
            hotkeyRegistrar.unregister(id: layout.commandID.rawValue)
            commandHotkeys[layout.commandID] = nil
            commandHotkeyErrors[layout.commandID] = nil
            hotkeyStore.setCommandHotkey(nil, for: layout.commandID)
            reloadApplications()
        } catch { workspacePlugin.statusMessage = error.localizedDescription }
    }

    func setScreenshotEnabled(_ enabled: Bool) {
        screenshotPlugin.setEnabled(enabled)
        if !enabled {
            for target in ScreenshotPlugin.shortcutTargets { hotkeyRegistrar.unregister(id: target.id.rawValue) }
            return
        }
        do {
            try applyHotkeyRegistrations()
            shortcutRegistrationError = nil
        } catch {
            screenshotPlugin.setEnabled(false)
            shortcutRegistrationError = error.localizedDescription
        }
    }

    func setClipboardHistoryEnabled(_ enabled: Bool) {
        clipboardHistoryPlugin.setEnabled(enabled)
        if !enabled {
            hotkeyRegistrar.unregister(id: ClipboardHistoryPlugin.commandID.rawValue)
            return
        }
        do {
            try applyHotkeyRegistrations()
            shortcutRegistrationError = nil
        }
        catch {
            clipboardHistoryPlugin.setEnabled(false)
            shortcutRegistrationError = error.localizedDescription
        }
    }

    func setTextLookupEnabled(_ isEnabled: Bool) {
        textLookupError = nil
        do {
            if isEnabled {
                refreshAccessibilityState()
                guard isAccessibilityTrusted else {
                    textLookupError = String(localized: "Accessibility permission is required to enable Text Lookup.")
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
        } catch {
            textLookupError = error.localizedDescription
        }
    }

    func setTextLookupShortcut(_ shortcut: TextLookupShortcutPreset) {
        textLookupError = nil
        do {
            try validateHotkeyAssignments(textLookupShortcut: shortcut)
            try textLookupPlugin.setShortcut(shortcut)
        } catch {
            textLookupError = error.localizedDescription
        }
    }

    func requestAccessibilityPermission() {
        accessibilityAuthorization.request()
        refreshAccessibilityState()
    }

    func openAccessibilitySettings() {
        accessibilityAuthorization.openSystemSettings()
    }

    func performCommandRecovery(_ action: CommandRecoveryAction) {
        switch action {
        case .openAccessibilitySettings:
            openAccessibilitySettings()
        case .openWorkspaceSettings:
            do { try openSettings(tab: .workspace) }
            catch { commandFeedback = CommandFeedbackMapper.failure(for: error) }
        case .openWindowManagementSettings:
            do {
                try openSettings(tab: .windowManagement)
            } catch {
                commandFeedback = CommandFeedbackMapper.failure(for: error)
            }
        }
    }

    func openSettings(tab: SettingsTab) throws {
        selectedSettingsTab = tab
        try settingsWindowOpener.open()
    }

    func reconcileAccessibilityDependentFeatures() {
        refreshAccessibilityState()
        windowManagementPlugin.reconcileAuthorization()
        guard !isAccessibilityTrusted else { return }

        setWorkspaceEnabled(false)
        let disabledTextLookup = textLookupPlugin.settings.isEnabled
        if disabledTextLookup {
            textLookupPlugin.settings.setEnabled(false)
            textLookupPlugin.stop()
            textLookupError = String(localized: "Accessibility-dependent features were disabled. Re-enable them after granting permission.")
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

        requests += windowManagementPlugin.hotkeyRequests(for: commandHotkeys) { [weak self] commandID in
            self?.executeDirectCommand(commandID)
        }

        if clipboardHistoryPlugin.isEnabled, let hotkey = commandHotkeys[ClipboardHistoryPlugin.commandID] {
            requests.append(HotkeyRegistrationRequest(id: ClipboardHistoryPlugin.commandID.rawValue,
                hotkey: hotkey, label: String(localized: "Clipboard History")) { [weak self] in
                self?.executeDirectCommand(ClipboardHistoryPlugin.commandID)
            })
        }
        if workspacePlugin.isEnabled {
            for target in workspacePlugin.shortcutTargets {
                if let hotkey = commandHotkeys[target.id] {
                    requests.append(HotkeyRegistrationRequest(id: target.id.rawValue, hotkey: hotkey, label: target.title) { [weak self] in
                        self?.executeDirectCommand(target.id)
                    })
                }
            }
        }
        if screenshotPlugin.isEnabled {
            for target in ScreenshotPlugin.shortcutTargets {
                if let hotkey = commandHotkeys[target.id] {
                    requests.append(HotkeyRegistrationRequest(id: target.id.rawValue, hotkey: hotkey, label: target.title) { [weak self] in
                        self?.executeDirectCommand(target.id)
                    })
                }
            }
        }
        let commandRegistrationIDs = Set(["root-search"] + commandShortcutTargets.map(\.id.rawValue))
        try hotkeyRegistrar.replace(ids: commandRegistrationIDs, with: requests)
    }

    private func validateHotkeyAssignments(
        textLookupShortcut: TextLookupShortcutPreset,
        textLookupEnabled: Bool? = nil
    ) throws {
        var assignments = [
            HotkeyAssignment(owner: String(localized: "Root Search"), hotkey: rootSearchHotkey),
        ] + commandShortcutTargets.map { target in
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

    private func executeDirectCommand(_ commandID: CommandID) {
        let context = CommandContext(
            source: .directHotkey,
            frontmostApplicationPID: NSWorkspace.shared.frontmostApplication?.processIdentifier
        )
        execute(
            commandID,
            context: context,
            hidePanelOnSuccess: false
        )
    }
}
