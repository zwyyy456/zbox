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
    let rootSearch: RootSearchSession
    private let hotkeyRegistrar: any HotkeyRegistering
    private let accessibilityAuthorization: AccessibilityAuthorization
    let settingsWindowOpener = SettingsWindowOpener()
    private let launchAtLoginController = LaunchAtLoginController()
    let aliasStore: CommandAliasStore
    var aliasSettingsTarget: CommandID?
    @ObservationIgnored private(set) lazy var hotkeys = CommandHotkeyController(
        store: HotkeyConfigurationStore(defaults: defaults), registrar: hotkeyRegistrar,
        applyRegistrations: { [weak self] in try self?.applyHotkeyRegistrations() },
        recordingChanged: { [weak self] in self?.textLookupPlugin.setShortcutRecordingActive($0) }
    )
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
    @ObservationIgnored
    let workspacePlugin: WorkspacePlugin
    @ObservationIgnored
    let displayPlugin: DisplayPlugin

    let appMenuPlugin: AppMenuPlugin
    let audioPlugin: AudioPlugin
    let extensionManager: ExtensionManager
    private var registeredExtensionIDs = Set<String>()
    private var registeredApplicationIDs = Set<String>()
    let scriptCommandsPlugin: ScriptCommandsPlugin
    let developerToolsPlugin: DeveloperToolsPlugin
    let fileSearchPlugin: FileSearchPlugin
    let snippetsPlugin: SnippetsPlugin
    let quicklinksPlugin: QuicklinksPlugin

    private var commandRegistry = CommandRegistry()
    private var applicationURLsByCommandID: [CommandID: URL] = [:]
    private(set) var applications: [ApplicationInfo] = []
    private(set) var applicationReloadError: String?
    private(set) var launchAtLoginError: String?
    private(set) var textLookupError: String?
    private(set) var isLaunchAtLoginEnabled = false
    private(set) var isAccessibilityTrusted: Bool
    private(set) var showsApplicationPathsInSearchResults: Bool
    var selectedSettingsTab: SettingsTab = .general
    var commandShortcutTargets: [CommandShortcutTarget] {
        commandShortcutSections.flatMap(\.targets)
    }

    private var applicationShortcutTargets: [CommandShortcutTarget] {
        let available = applications.map {
            CommandShortcutTarget(id: ApplicationCommands.id(for: $0), title: $0.name)
        }
        let known = Set(available.map(\.id))
        let unavailable = hotkeys.commandHotkeys.keys
            .filter { ApplicationCommands.owns($0) && !known.contains($0) }
            .sorted { $0.rawValue < $1.rawValue }
            .map { CommandShortcutTarget(id: $0, title: $0.rawValue) }
        return available + unavailable
    }

    /// Shortcut targets grouped by owning plugin or application.
    var commandShortcutSections: [(title: String, targets: [CommandShortcutTarget])] {
        [
            (String(localized: "Extensions"), extensionManager.shortcutTargets),
            (String(localized: "Application Menu"), [AppMenuPlugin.shortcutTarget]),
            (String(localized: "Audio"), AudioPlugin.shortcutTargets),
            (String(localized: "Automation"), scriptCommandsPlugin.shortcutTargets),
            (String(localized: "Developer Tools"), DeveloperToolsPlugin.shortcutTargets),
            (String(localized: "File Search"), FileSearchPlugin.shortcutTargets),
            (String(localized: "Snippets"), snippetsPlugin.shortcutTargets),
            (String(localized: "Quicklinks"), quicklinksPlugin.shortcutTargets),
            (String(localized: "Display"), displayPlugin.shortcutTargets),
            (String(localized: "Workspace"), workspacePlugin.shortcutTargets),
            (String(localized: "Screenshot"), ScreenshotPlugin.shortcutTargets),
            (String(localized: "Window Management"), WindowCommands.shortcutTargets),
            (String(localized: "Clipboard History"),
             [CommandShortcutTarget(id: ClipboardHistoryPlugin.commandID, title: String(localized: "Clipboard History"))]),
            (String(localized: "Applications"), applicationShortcutTargets),
        ].filter { !$0.1.isEmpty }
    }

    var commandConfigurationSections: [(title: String, targets: [CommandShortcutTarget])] {
        var sections = commandShortcutSections
        var known = Set(sections.flatMap { $0.targets.map(\.id) })
        for descriptor in commandRegistry.descriptors where known.insert(descriptor.id).inserted {
            let title = accessoryTitle(for: descriptor)
            let target = CommandShortcutTarget(id: descriptor.id, title: descriptor.title)
            if let index = sections.firstIndex(where: { $0.title == title }) {
                sections[index].targets.append(target)
            } else {
                sections.append((title, [target]))
            }
        }
        let missing = aliasStore.aliases.keys.filter { !known.contains($0) }
            .sorted { $0.rawValue < $1.rawValue }
        if !missing.isEmpty {
            sections.append((String(localized: "Currently Unavailable"),
                missing.map { CommandShortcutTarget(id: $0, title: $0.rawValue) }))
        }
        return sections
    }

    /// Whether the plugin behind a settings tab is turned on; nil for tabs without an on/off switch.
    func isPluginEnabled(_ tab: SettingsTab) -> Bool? {
        switch tab {
        case .general, .shortcuts, .extensions: nil
        case .appMenu: appMenuPlugin.isEnabled
        case .audio: audioPlugin.isEnabled
        case .scriptCommands: scriptCommandsPlugin.isEnabled
        case .fileSearch: fileSearchPlugin.isEnabled
        case .snippets: snippetsPlugin.isEnabled
        case .quicklinks: quicklinksPlugin.isEnabled
        case .display: displayPlugin.isEnabled
        case .workspace: workspacePlugin.isEnabled
        case .windowManagement: windowManagementPlugin.isEnabled
        case .textLookup: textLookupPlugin.settings.isEnabled
        case .screenshot: screenshotPlugin.isEnabled
        case .clipboardHistory: clipboardHistoryPlugin.isEnabled
        }
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
    private var hasStarted = false

    init(
        defaults: UserDefaults = .standard,
        hotkeyRegistrar: any HotkeyRegistering = GlobalHotkeyRegistrar()
    ) {
        appMenuPlugin = AppMenuPlugin(defaults: defaults)
        audioPlugin = AudioPlugin(defaults: defaults)
        let clipboardCoordinator = ClipboardAccessCoordinator()
        self.clipboardCoordinator = clipboardCoordinator
        extensionManager = ExtensionManager(coordinator: clipboardCoordinator)
        let scriptCommandsPlugin = ScriptCommandsPlugin(defaults: defaults, coordinator: clipboardCoordinator)
        self.scriptCommandsPlugin = scriptCommandsPlugin
        developerToolsPlugin = DeveloperToolsPlugin(clipboardCoordinator: clipboardCoordinator)
        fileSearchPlugin = FileSearchPlugin(defaults: defaults, coordinator: clipboardCoordinator)
        let snippetsPlugin = SnippetsPlugin(defaults: defaults, coordinator: clipboardCoordinator)
        self.snippetsPlugin = snippetsPlugin
        let quicklinksPlugin = QuicklinksPlugin(defaults: defaults)
        self.quicklinksPlugin = quicklinksPlugin
        let displayPlugin = DisplayPlugin(defaults: defaults)
        self.displayPlugin = displayPlugin
        let workspacePlugin = WorkspacePlugin(defaults: defaults)
        self.workspacePlugin = workspacePlugin
        screenshotPlugin = ScreenshotPlugin(defaults: defaults, clipboardCoordinator: clipboardCoordinator)
        let accessibilityAuthorization = AccessibilityAuthorization()
        clipboardHistoryPlugin = ClipboardHistoryPlugin(defaults: defaults, coordinator: clipboardCoordinator,
                                                        authorization: accessibilityAuthorization)
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
        self.defaults = defaults
        aliasStore = CommandAliasStore(defaults: defaults)
        self.textLookupPlugin = textLookupPlugin
        rootSearch = RootSearchSession(defaults: defaults, aliases: aliasStore)
        isAccessibilityTrusted = accessibilityAuthorization.isTrusted
        showsApplicationPathsInSearchResults = defaults.bool(forKey: Key.showApplicationPaths)

        hotkeys.loadCommands(commandShortcutTargets.map(\.id))
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        extensionManager.applyCommands = { [weak self] commandIDs in
            guard let self else { return }
            hotkeys.loadCommands(extensionManager.shortcutTargets.map(\.id))
            try rebuildCommandRegistry()
            let ids = Set(commandIDs.map(\.rawValue))
            let requests = extensionHotkeyRequests().filter { ids.contains($0.id) }
            if !requests.isEmpty {
                try validateHotkeyAssignments(textLookupTriggers: textLookupPlugin.settings.triggers)
            }
            try hotkeyRegistrar.replace(ids: ids, with: requests)
            registeredExtensionIDs.subtract(ids)
            registeredExtensionIDs.formUnion(requests.map(\.id))
        }
        extensionManager.didCommit = { [weak self] removed in
            guard let self else { return }
            for id in removed {
                aliasStore.remove(id)
                hotkeys.forget(id)
            }
        }
        Task { await extensionManager.load() }
        workspacePlugin.onCompletion = { [weak self] message, permissionLost in
            guard let self else { return }
            if permissionLost { reconcileAccessibilityDependentFeatures() }
            if let message {
                commandFeedbackPanelController.show(CommandFeedback(message: message, recoveryAction: .openWorkspaceSettings))
            }
        }
        reconcileAccessibilityDependentFeatures()
        audioPlugin.start()
        windowManagementPlugin.start()
        if displayPlugin.isEnabled { displayPlugin.start() }
        fileSearchPlugin.start()
        clipboardHistoryPlugin.start()
        reloadApplications()
        isLaunchAtLoginEnabled = launchAtLoginController.isEnabled

        do {
            try applyHotkeyRegistrations()
        } catch {
            hotkeys.shortcutRegistrationError = error.localizedDescription
        }

        if textLookupPlugin.settings.isEnabled, isAccessibilityTrusted {
            textLookupPlugin.start()
        }
    }

    func stop() {
        launchTask?.cancel()
        commandExecutionID = nil
        rootSearch.end()
        commandFeedbackPanelController.hide()
        appMenuPlugin.stop()
        audioPlugin.stop()
        textLookupPlugin.stop()
        fileSearchPlugin.stop()
        snippetsPlugin.stop()
        quicklinksPlugin.stop()
        calculatorPlugin.stop()
        developerToolsPlugin.stop()
        extensionManager.stop()
        scriptCommandsPlugin.stop()
        windowManagementPlugin.stop()
        clipboardHistoryPlugin.stop()
        screenshotPlugin.stop()
        workspacePlugin.stop()
        displayPlugin.stop()
        hotkeyRegistrar.unregisterAll()
    }

    func toggleRootSearch() {
        if searchPanelController.isVisible {
            hideRootSearch()
            return
        }

        showRootSearch()
    }

    func showRootSearch() {
        if searchPanelController.isVisible {
            searchPanelController.show()
            return
        }
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        rootSearch.begin(targetPID: frontmostPID == ProcessInfo.processInfo.processIdentifier ? nil : frontmostPID)
        commandFeedbackPanelController.hide()
        searchPanelController.show()
    }

    func hideRootSearch() {
        rootSearch.end()
        searchPanelController.hide()
    }

    func reloadApplications() {
        updateApplications(applicationCatalog.loadApplications())
    }

    func updateApplications(_ applications: [ApplicationInfo]) {
        self.applications = applications
        do {
            try rebuildCommandRegistry()
            let availableIDs = Set(applications.map { ApplicationCommands.id(for: $0).rawValue })
            let removedIDs = registeredApplicationIDs.subtracting(availableIDs)
            for id in removedIDs { hotkeyRegistrar.unregister(id: id) }
            registeredApplicationIDs.subtract(removedIDs)
            try applyHotkeyRegistrations()
        } catch {
            applicationReloadError = error.localizedDescription
        }
    }

    private func rebuildCommandRegistry() throws {
        let registry = CommandRegistry()
        var applicationURLs: [CommandID: URL] = [:]

        try extensionManager.register(in: registry)
        try appMenuPlugin.register(in: registry) { [weak self] in try self?.openSettings(tab: .appMenu) }
        try audioPlugin.register(in: registry) { [weak self] in try self?.openSettings(tab: .audio) }
        try windowManagementPlugin.register(in: registry)
        try SettingsCommands.register(in: registry) { [weak self] in
            try self?.openSettings(tab: .general)
        }
        try fileSearchPlugin.register(in: registry) { [weak self] in
            try self?.openSettings(tab: .fileSearch)
        }
        try snippetsPlugin.register(in: registry) { [weak self] in
            try self?.openSettings(tab: .snippets)
        }
        try quicklinksPlugin.register(in: registry) { [weak self] in
            try self?.openSettings(tab: .quicklinks)
        }
        try calculatorPlugin.register(in: registry)
        try developerToolsPlugin.register(in: registry)
        try scriptCommandsPlugin.register(in: registry) { [weak self] in try self?.openSettings(tab: .scriptCommands) }
        try displayPlugin.register(in: registry) { [weak self] in
            try self?.openSettings(tab: .display)
        }
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
        rootSearch.descriptors = registry.descriptors
        applicationURLsByCommandID = applicationURLs
        applicationReloadError = nil
    }

    func moveSelection(by offset: Int) {
        if rootSearch.isShowingRootSearchActions, let selected = rootSearch.selectedSearchMatch {
            let count = rootSearchActions(for: selected.id).count
            rootSearch.selectedRootSearchActionIndex = min(max(rootSearch.selectedRootSearchActionIndex + offset, 0), max(count - 1, 0))
            return
        }
        rootSearch.moveSelection(by: offset)
    }

    func executeSelectedCommand() {
        guard let commandID = rootSearch.selectedSearchMatch?.id else {
            return
        }

        let context = CommandContext(
            source: .rootSearch,
            frontmostApplicationPID: rootSearch.targetApplicationPID
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
        let expectedRootSearchSessionID = hidePanelOnSuccess ? rootSearch.id : nil
        launchTask?.cancel()
        if context.source == .directHotkey {
            commandFeedbackPanelController.hide()
        }
        commandExecutionID = executionID
        launchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await registry.execute(commandID, context: context)
                if context.source == .rootSearch { rootSearch.recordRecentCommand(commandID) }
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
                    rootSearch.commandFeedback = feedback
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
            || rootSearch.id == expectedRootSearchSessionID
    }

    func primaryActionTitle(for descriptor: CommandDescriptor) -> String {
        applicationURLsByCommandID[descriptor.id] != nil
            ? String(localized: "Open Application")
            : String(localized: "Run Command")
    }

    /// Plugin or result type shown at the trailing edge of a Root Search row.
    func accessoryTitle(for descriptor: CommandDescriptor) -> String {
        if applicationURLsByCommandID[descriptor.id] != nil { return String(localized: "Application") }
        return descriptor.category ?? String(localized: "Command")
    }

    func rootSearchActions(for commandID: CommandID) -> [RootSearchAction] {
        guard let url = applicationURLsByCommandID[commandID] else { return [.editAlias] }
        let isRunning = NSWorkspace.shared.runningApplications.contains { $0.bundleURL == url }
        return [.open, .showInFinder, .copyPath] + (isRunning ? [.quit] : []) + [.editAlias]
    }

    func performSelectedRootSearchAction() {
        guard let selected = rootSearch.selectedSearchMatch else { return }
        let actions = rootSearchActions(for: selected.id)
        guard actions.indices.contains(rootSearch.selectedRootSearchActionIndex) else { return }
        performRootSearchAction(actions[rootSearch.selectedRootSearchActionIndex])
    }

    func performRootSearchAction(_ action: RootSearchAction) {
        rootSearch.isShowingRootSearchActions = false
        guard let match = rootSearch.selectedSearchMatch else { return }
        if action == .editAlias {
            aliasSettingsTarget = match.id
            hideRootSearch()
            do { try openSettings(tab: .shortcuts) }
            catch { applicationReloadError = error.localizedDescription }
            return
        }
        guard action != .open, let url = applicationURLsByCommandID[match.id] else {
            executeSelectedCommand()
            return
        }
        switch action {
        case .open, .editAlias:
            return
        case .showInFinder:
            NSWorkspace.shared.activateFileViewerSelecting([url])
        case .copyPath:
            let board = NSPasteboard.general
            board.clearContents()
            board.setString(url.path, forType: .string)
            clipboardCoordinator.didWrite(changeCount: board.changeCount)
        case .quit:
            NSWorkspace.shared.runningApplications.filter { $0.bundleURL == url }.forEach { $0.terminate() }
        }
        rootSearch.recordRecentCommand(match.id)
        hideRootSearch()
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


    func commandHotkey(for commandID: CommandID) -> Hotkey? {
        hotkeys.commandHotkeys[commandID]
    }

    func setApplicationConfiguration(alias: String, hotkey: Hotkey?, for id: CommandID) throws {
        try hotkeys.setApplicationConfiguration(alias: alias, hotkey: hotkey, for: id, aliasStore: aliasStore)
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

    func setAppMenuEnabled(_ enabled: Bool) {
        refreshAccessibilityState()
        appMenuPlugin.setEnabled(enabled)
        if !appMenuPlugin.isEnabled {
            hotkeyRegistrar.unregister(id: AppMenuPlugin.commandID.rawValue)
            return
        }
        do { try applyHotkeyRegistrations(); hotkeys.shortcutRegistrationError = nil }
        catch { appMenuPlugin.setEnabled(false); hotkeys.shortcutRegistrationError = error.localizedDescription }
    }

    func setAudioEnabled(_ enabled: Bool) {
        audioPlugin.setEnabled(enabled)
        if !enabled {
            for target in AudioPlugin.shortcutTargets { hotkeyRegistrar.unregister(id: target.id.rawValue) }
            return
        }
        do { try applyHotkeyRegistrations(); hotkeys.shortcutRegistrationError = nil }
        catch { audioPlugin.setEnabled(false); hotkeys.shortcutRegistrationError = error.localizedDescription }
    }

    func setFileSearchEnabled(_ enabled: Bool) {
        let previous = fileSearchPlugin.isEnabled
        fileSearchPlugin.setEnabled(enabled)
        if enabled {
            do { try applyHotkeyRegistrations(); fileSearchPlugin.statusMessage = nil }
            catch {
                fileSearchPlugin.setEnabled(previous)
                fileSearchPlugin.statusMessage = error.localizedDescription
            }
        } else {
            for target in FileSearchPlugin.shortcutTargets { hotkeyRegistrar.unregister(id: target.id.rawValue) }
        }
    }

    func setSnippetsEnabled(_ enabled: Bool) {
        let previous = snippetsPlugin.isEnabled
        snippetsPlugin.setEnabled(enabled)
        if enabled {
            do { try applyHotkeyRegistrations(); snippetsPlugin.statusMessage = nil }
            catch {
                snippetsPlugin.setEnabled(previous)
                snippetsPlugin.statusMessage = error.localizedDescription
            }
        } else {
            for target in snippetsPlugin.shortcutTargets { hotkeyRegistrar.unregister(id: target.id.rawValue) }
        }
        do { try rebuildCommandRegistry() }
        catch { applicationReloadError = error.localizedDescription }
    }

    func saveSnippet(_ item: Snippet) -> Bool {
        snippetsPlugin.save(item, updateCommands: rebuildCommandRegistry)
    }

    func deleteSnippet(_ item: Snippet) {
        snippetsPlugin.delete(item) {
            removeCommandHotkey(item.commandID)
            try rebuildCommandRegistry()
        }
    }

    func setScriptCommandsEnabled(_ enabled: Bool) {
        let previous = scriptCommandsPlugin.isEnabled
        scriptCommandsPlugin.setEnabled(enabled)
        if enabled {
            do { try applyHotkeyRegistrations(); scriptCommandsPlugin.statusMessage = nil }
            catch {
                scriptCommandsPlugin.setEnabled(previous)
                scriptCommandsPlugin.statusMessage = error.localizedDescription
            }
        } else {
            for target in scriptCommandsPlugin.shortcutTargets { hotkeyRegistrar.unregister(id: target.id.rawValue) }
        }
        do { try rebuildCommandRegistry() }
        catch { applicationReloadError = error.localizedDescription }
    }

    func saveScriptCommand(_ item: ScriptCommand) -> Bool {
        scriptCommandsPlugin.save(item, registerHotkeys: applyHotkeyRegistrations, updateCommands: rebuildCommandRegistry)
    }

    func deleteScriptCommand(_ item: ScriptCommand) {
        scriptCommandsPlugin.delete(item) {
            removeCommandHotkey(item.commandID)
            try rebuildCommandRegistry()
        }
    }

    func setQuicklinksEnabled(_ enabled: Bool) {
        let previous = quicklinksPlugin.isEnabled
        quicklinksPlugin.setEnabled(enabled)
        if enabled {
            do { try applyHotkeyRegistrations(); quicklinksPlugin.statusMessage = nil }
            catch {
                quicklinksPlugin.setEnabled(previous)
                quicklinksPlugin.statusMessage = error.localizedDescription
            }
        } else {
            for target in quicklinksPlugin.shortcutTargets { hotkeyRegistrar.unregister(id: target.id.rawValue) }
        }
        do { try rebuildCommandRegistry() }
        catch { applicationReloadError = error.localizedDescription }
    }

    func saveQuicklink(_ item: Quicklink) -> Bool {
        quicklinksPlugin.save(item, updateCommands: rebuildCommandRegistry)
    }

    func deleteQuicklink(_ item: Quicklink) {
        quicklinksPlugin.delete(item) {
            removeCommandHotkey(item.commandID)
            try rebuildCommandRegistry()
        }
    }

    func setDisplayEnabled(_ enabled: Bool) {
        displayPlugin.setEnabled(enabled)
        if !displayPlugin.isEnabled {
            for target in displayPlugin.shortcutTargets { hotkeyRegistrar.unregister(id: target.id.rawValue) }
            return
        }
        do { try applyHotkeyRegistrations() }
        catch {
            displayPlugin.setEnabled(false)
            displayPlugin.statusMessage = error.localizedDescription
        }
    }

    func applyDisplayPreset(_ preset: DisplayPreset) { executeDirectCommand(preset.commandID) }

    func saveDisplayPreset(_ preset: DisplayPreset) -> Bool {
        displayPlugin.save(preset, updateCommands: rebuildCommandRegistry)
    }

    func deleteDisplayPreset(_ preset: DisplayPreset) {
        displayPlugin.delete(preset) {
            removeCommandHotkey(preset.commandID)
            try rebuildCommandRegistry()
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

    func saveWorkspace(_ layout: WorkspaceLayout) -> Bool {
        workspacePlugin.save(layout, updateCommands: rebuildCommandRegistry)
    }

    func deleteWorkspace(_ layout: WorkspaceLayout) {
        workspacePlugin.delete(layout) {
            removeCommandHotkey(layout.commandID)
            try rebuildCommandRegistry()
        }
    }

    func setScreenshotEnabled(_ enabled: Bool) {
        screenshotPlugin.setEnabled(enabled)
        if !enabled {
            for target in ScreenshotPlugin.shortcutTargets { hotkeyRegistrar.unregister(id: target.id.rawValue) }
            return
        }
        do {
            try applyHotkeyRegistrations()
            hotkeys.shortcutRegistrationError = nil
        } catch {
            screenshotPlugin.setEnabled(false)
            hotkeys.shortcutRegistrationError = error.localizedDescription
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
            hotkeys.shortcutRegistrationError = nil
        }
        catch {
            clipboardHistoryPlugin.setEnabled(false)
            hotkeys.shortcutRegistrationError = error.localizedDescription
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
                    textLookupTriggers: textLookupPlugin.settings.triggers,
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

    func setTextLookupTriggers(_ triggers: TextLookupTriggers) {
        textLookupError = nil
        do {
            try validateHotkeyAssignments(textLookupTriggers: triggers)
            try textLookupPlugin.setTriggers(triggers)
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
        case .openDisplaySettings:
            do { try openSettings(tab: .display) }
            catch { rootSearch.commandFeedback = CommandFeedbackMapper.failure(for: error) }
        case .openWorkspaceSettings:
            do { try openSettings(tab: .workspace) }
            catch { rootSearch.commandFeedback = CommandFeedbackMapper.failure(for: error) }
        case .openWindowManagementSettings:
            do {
                try openSettings(tab: .windowManagement)
            } catch {
                rootSearch.commandFeedback = CommandFeedbackMapper.failure(for: error)
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

        setAppMenuEnabled(false)
        setWorkspaceEnabled(false)
        let disabledTextLookup = textLookupPlugin.settings.isEnabled
        if disabledTextLookup {
            textLookupPlugin.settings.setEnabled(false)
            textLookupPlugin.stop()
            textLookupError = String(localized: "Accessibility-dependent features were disabled. Re-enable them after granting permission.")
        }
    }

    private func removeCommandHotkey(_ id: CommandID) {
        aliasStore.remove(id)
        hotkeyRegistrar.unregister(id: id.rawValue)
        hotkeys.forget(id)
    }

    private func applyHotkeyRegistrations() throws {
        try validateHotkeyAssignments(textLookupTriggers: textLookupPlugin.settings.triggers)

        var requests: [HotkeyRegistrationRequest] = []
        requests.append(
            HotkeyRegistrationRequest(
                id: "root-search",
                hotkey: hotkeys.rootSearchHotkey,
                label: HotkeyFormatter.displayName(for: hotkeys.rootSearchHotkey)
            ) { [weak self] in
                self?.toggleRootSearch()
            }
        )

        requests += windowManagementPlugin.hotkeyRequests(for: hotkeys.commandHotkeys) { [weak self] commandID in
            self?.executeDirectCommand(commandID)
        }

        if clipboardHistoryPlugin.isEnabled, let hotkey = hotkeys.commandHotkeys[ClipboardHistoryPlugin.commandID] {
            requests.append(HotkeyRegistrationRequest(id: ClipboardHistoryPlugin.commandID.rawValue,
                hotkey: hotkey, label: String(localized: "Clipboard History")) { [weak self] in
                self?.executeDirectCommand(ClipboardHistoryPlugin.commandID)
            })
        }
        if fileSearchPlugin.isEnabled {
            requests += commandHotkeyRequests(for: FileSearchPlugin.shortcutTargets)
        }
        if appMenuPlugin.isEnabled, isAccessibilityTrusted, let hotkey = hotkeys.commandHotkeys[AppMenuPlugin.commandID] {
            requests.append(HotkeyRegistrationRequest(id: AppMenuPlugin.commandID.rawValue, hotkey: hotkey,
                label: AppMenuPlugin.shortcutTarget.title) { [weak self] in self?.executeDirectCommand(AppMenuPlugin.commandID) })
        }
        if audioPlugin.isEnabled {
            requests += commandHotkeyRequests(for: AudioPlugin.shortcutTargets)
        }
        requests += commandHotkeyRequests(for: DeveloperToolsPlugin.shortcutTargets)

        if snippetsPlugin.isEnabled {
            requests += commandHotkeyRequests(for: snippetsPlugin.shortcutTargets)
        }
        if scriptCommandsPlugin.isEnabled {
            requests += commandHotkeyRequests(for: scriptCommandsPlugin.enabledShortcutTargets)
        }
        if quicklinksPlugin.isEnabled {
            requests += commandHotkeyRequests(for: quicklinksPlugin.shortcutTargets)
        }
        if displayPlugin.isEnabled {
            requests += commandHotkeyRequests(for: displayPlugin.shortcutTargets)
        }
        if workspacePlugin.isEnabled {
            requests += commandHotkeyRequests(for: workspacePlugin.shortcutTargets)
        }
        if screenshotPlugin.isEnabled {
            requests += commandHotkeyRequests(for: ScreenshotPlugin.shortcutTargets)
        }
        requests += extensionHotkeyRequests()
        let availableApplications = applicationShortcutTargets.filter { applicationURLsByCommandID[$0.id] != nil }
        requests += commandHotkeyRequests(for: availableApplications)
        let commandRegistrationIDs = Set(["root-search"] + commandShortcutTargets.map(\.id.rawValue)).union(registeredExtensionIDs).union(registeredApplicationIDs)
        try hotkeyRegistrar.replace(ids: commandRegistrationIDs, with: requests)
        registeredExtensionIDs = Set(extensionManager.shortcutTargets.map(\.id.rawValue))
        registeredApplicationIDs = Set(availableApplications.filter { hotkeys.commandHotkeys[$0.id] != nil }.map(\.id.rawValue))
    }

    private func commandHotkeyRequests(for targets: [CommandShortcutTarget]) -> [HotkeyRegistrationRequest] {
        targets.compactMap { target in
            guard let hotkey = hotkeys.commandHotkeys[target.id] else { return nil }
            return HotkeyRegistrationRequest(id: target.id.rawValue, hotkey: hotkey, label: target.title) { [weak self] in
                self?.executeDirectCommand(target.id)
            }
        }
    }

    private func extensionHotkeyRequests() -> [HotkeyRegistrationRequest] {
        let enabledIDs = extensionManager.enabledCommandIDs
        return commandHotkeyRequests(for: extensionManager.shortcutTargets.filter { enabledIDs.contains($0.id) })
    }

    private func validateHotkeyAssignments(textLookupTriggers: TextLookupTriggers,
                                          textLookupEnabled: Bool? = nil) throws {
        try hotkeys.validate(targets: commandShortcutTargets, textLookupTriggers: textLookupTriggers,
                             textLookupEnabled: textLookupEnabled ?? textLookupPlugin.settings.isEnabled)
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
