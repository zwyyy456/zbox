import AppKit
import Observation

@MainActor
@Observable
final class AppEnvironment {
    private enum Key {
        static let showApplicationPaths = "search.show-application-paths"
        static let recentCommands = "search.recent-command-ids"
    }

    private enum RootSearchLimit {
        static let results = 8
        static let recent = 5
    }

    /// Entry commands suggested on an empty query after recent commands.
    private static let suggestedCommandIDs = [
        FileSearchPlugin.commandID, ClipboardHistoryPlugin.commandID, SnippetsPlugin.commandID,
        CalculatorPlugin.commandID, DeveloperToolsPlugin.commandID, SettingsCommands.openID,
    ]

    private let clipboardCoordinator: ClipboardAccessCoordinator
    private let applicationCatalog = ApplicationCatalog()
    private let applicationLauncher = ApplicationLauncher()
    private let applicationIconProvider = ApplicationIconProvider()
    private let searchEngine = SearchEngine()
    private let hotkeyRegistrar: any HotkeyRegistering
    private let accessibilityAuthorization: AccessibilityAuthorization
    let settingsWindowOpener = SettingsWindowOpener()
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
    @ObservationIgnored
    let workspacePlugin: WorkspacePlugin
    @ObservationIgnored
    let displayPlugin: DisplayPlugin

    let appMenuPlugin: AppMenuPlugin
    let audioPlugin: AudioPlugin
    let extensionManager: ExtensionManager
    private var registeredExtensionIDs = Set<String>()
    let scriptCommandsPlugin: ScriptCommandsPlugin
    let developerToolsPlugin: DeveloperToolsPlugin
    let fileSearchPlugin: FileSearchPlugin
    let snippetsPlugin: SnippetsPlugin
    let quicklinksPlugin: QuicklinksPlugin

    private var commandRegistry = CommandRegistry()
    private var applicationURLsByCommandID: [CommandID: URL] = [:]
    private(set) var applications: [ApplicationInfo] = []
    private(set) var targetApplicationPID: pid_t?
    private(set) var selectedCommandID: CommandID?
    private(set) var rootSearchHotkey: Hotkey
    private(set) var commandHotkeys: [CommandID: Hotkey] = [:]
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
    private(set) var recentCommandIDs: [CommandID]
    var isShowingRootSearchActions = false {
        didSet { selectedRootSearchActionIndex = 0 }
    }
    private(set) var selectedRootSearchActionIndex = 0
    var selectedSettingsTab: SettingsTab = .general
    var commandShortcutTargets: [CommandShortcutTarget] {
        commandShortcutSections.flatMap(\.targets)
    }

    /// Shortcut targets grouped by owning plugin.
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
        ].filter { !$0.1.isEmpty }
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

    var searchQuery = "" {
        didSet {
            if searchQuery != oldValue {
                selectedCommandID = nil
                isShowingRootSearchActions = false
            }
        }
    }
    var searchResultSections: [SearchResultSection] {
        let descriptors = commandRegistry.descriptors
        guard searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let matches = searchEngine.search(query: searchQuery, in: descriptors, limit: RootSearchLimit.results)
            return matches.isEmpty ? [] : [SearchResultSection(title: nil, matches: matches)]
        }

        let byID = Dictionary(descriptors.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let recent = recentCommandIDs.compactMap { byID[$0] }.prefix(RootSearchLimit.recent)
        let recentIDs = Set(recent.map(\.id))
        let suggested = Self.suggestedCommandIDs
            .filter { !recentIDs.contains($0) }
            .compactMap { byID[$0] }
            .prefix(RootSearchLimit.results - recent.count)
        return [
            SearchResultSection(title: String(localized: "Recent"),
                                matches: recent.map { SearchMatch(descriptor: $0, score: 0) }),
            SearchResultSection(title: String(localized: "Suggestions"),
                                matches: suggested.map { SearchMatch(descriptor: $0, score: 0) }),
        ].filter { !$0.matches.isEmpty }
    }

    var searchResults: [SearchMatch] {
        searchResultSections.flatMap(\.matches)
    }

    var selectedSearchMatch: SearchMatch? {
        let results = searchResults
        return results.first { $0.id == selectedCommandID } ?? results.first
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
        recentCommandIDs = (defaults.stringArray(forKey: Key.recentCommands) ?? []).map(CommandID.init)
        commandHotkeys = hotkeyStore.commandHotkeys(for: commandShortcutTargets.map(\.id))
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        extensionManager.applyCommands = { [weak self] commandIDs in
            guard let self else { return }
            for target in extensionManager.shortcutTargets where commandHotkeys[target.id] == nil {
                commandHotkeys[target.id] = hotkeyStore.commandHotkeys(for: [target.id])[target.id]
            }
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
                commandHotkeys[id] = nil
                commandHotkeyErrors[id] = nil
                hotkeyStore.setCommandHotkey(nil, for: id)
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
        rootSearchSessionID = UUID()
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        targetApplicationPID = frontmostPID == ProcessInfo.processInfo.processIdentifier ? nil : frontmostPID
        searchQuery = ""
        selectedCommandID = nil
        isShowingRootSearchActions = false
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
        do { try rebuildCommandRegistry() }
        catch { applicationReloadError = error.localizedDescription }
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
        applicationURLsByCommandID = applicationURLs
        applicationReloadError = nil
    }

    func select(_ commandID: CommandID) {
        selectedCommandID = commandID
    }


    func moveSelection(by offset: Int) {
        if isShowingRootSearchActions, let selected = selectedSearchMatch {
            let count = rootSearchActions(for: selected.id).count
            selectedRootSearchActionIndex = min(max(selectedRootSearchActionIndex + offset, 0), max(count - 1, 0))
            return
        }
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
        guard let commandID = selectedSearchMatch?.id else {
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
                if context.source == .rootSearch { recordRecentCommand(commandID) }
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

    private func recordRecentCommand(_ commandID: CommandID) {
        recentCommandIDs.removeAll { $0 == commandID }
        recentCommandIDs.insert(commandID, at: 0)
        recentCommandIDs = Array(recentCommandIDs.prefix(RootSearchLimit.recent * 4))
        defaults.set(recentCommandIDs.map(\.rawValue), forKey: Key.recentCommands)
    }

    func clearRecentCommands() {
        recentCommandIDs = []
        defaults.removeObject(forKey: Key.recentCommands)
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
        guard let url = applicationURLsByCommandID[commandID] else { return [] }
        let isRunning = NSWorkspace.shared.runningApplications.contains { $0.bundleURL == url }
        return [.open, .showInFinder, .copyPath] + (isRunning ? [.quit] : [])
    }

    func performSelectedRootSearchAction() {
        guard let selected = selectedSearchMatch else { return }
        let actions = rootSearchActions(for: selected.id)
        guard actions.indices.contains(selectedRootSearchActionIndex) else { return }
        performRootSearchAction(actions[selectedRootSearchActionIndex])
    }

    func performRootSearchAction(_ action: RootSearchAction) {
        isShowingRootSearchActions = false
        guard let match = selectedSearchMatch else { return }
        guard action != .open, let url = applicationURLsByCommandID[match.id] else {
            executeSelectedCommand()
            return
        }
        switch action {
        case .open:
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
        recordRecentCommand(match.id)
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
        textLookupPlugin.setShortcutRecordingActive(isActive)

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

    func setAppMenuEnabled(_ enabled: Bool) {
        refreshAccessibilityState()
        appMenuPlugin.setEnabled(enabled)
        if !appMenuPlugin.isEnabled {
            hotkeyRegistrar.unregister(id: AppMenuPlugin.commandID.rawValue)
            return
        }
        do { try applyHotkeyRegistrations(); shortcutRegistrationError = nil }
        catch { appMenuPlugin.setEnabled(false); shortcutRegistrationError = error.localizedDescription }
    }

    func setAudioEnabled(_ enabled: Bool) {
        audioPlugin.setEnabled(enabled)
        if !enabled {
            for target in AudioPlugin.shortcutTargets { hotkeyRegistrar.unregister(id: target.id.rawValue) }
            return
        }
        do { try applyHotkeyRegistrations(); shortcutRegistrationError = nil }
        catch { audioPlugin.setEnabled(false); shortcutRegistrationError = error.localizedDescription }
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
            catch { commandFeedback = CommandFeedbackMapper.failure(for: error) }
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
        hotkeyRegistrar.unregister(id: id.rawValue)
        commandHotkeys[id] = nil
        commandHotkeyErrors[id] = nil
        hotkeyStore.setCommandHotkey(nil, for: id)
    }

    private func applyHotkeyRegistrations() throws {
        try validateHotkeyAssignments(textLookupTriggers: textLookupPlugin.settings.triggers)

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
        if fileSearchPlugin.isEnabled {
            requests += commandHotkeyRequests(for: FileSearchPlugin.shortcutTargets)
        }
        if appMenuPlugin.isEnabled, isAccessibilityTrusted, let hotkey = commandHotkeys[AppMenuPlugin.commandID] {
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
        let commandRegistrationIDs = Set(["root-search"] + commandShortcutTargets.map(\.id.rawValue)).union(registeredExtensionIDs)
        try hotkeyRegistrar.replace(ids: commandRegistrationIDs, with: requests)
        registeredExtensionIDs = Set(extensionManager.shortcutTargets.map(\.id.rawValue))
    }

    private func commandHotkeyRequests(for targets: [CommandShortcutTarget]) -> [HotkeyRegistrationRequest] {
        targets.compactMap { target in
            guard let hotkey = commandHotkeys[target.id] else { return nil }
            return HotkeyRegistrationRequest(id: target.id.rawValue, hotkey: hotkey, label: target.title) { [weak self] in
                self?.executeDirectCommand(target.id)
            }
        }
    }

    private func extensionHotkeyRequests() -> [HotkeyRegistrationRequest] {
        let enabledIDs = extensionManager.enabledCommandIDs
        return commandHotkeyRequests(for: extensionManager.shortcutTargets.filter { enabledIDs.contains($0.id) })
    }

    private func validateHotkeyAssignments(
        textLookupTriggers: TextLookupTriggers,
        textLookupEnabled: Bool? = nil
    ) throws {
        var assignments = [
            HotkeyAssignment(owner: String(localized: "Root Search"), hotkey: rootSearchHotkey),
        ] + commandShortcutTargets.map { target in
            HotkeyAssignment(owner: target.title, hotkey: commandHotkey(for: target.id))
        }
        if textLookupEnabled ?? textLookupPlugin.settings.isEnabled {
            try textLookupTriggers.validate()
            var lookupHotkeys: Set<Hotkey> = []
            for (owner, shortcut) in textLookupTriggers.activeShortcuts {
                if let hotkey = shortcut.hotkey, lookupHotkeys.insert(hotkey).inserted {
                    assignments.append(HotkeyAssignment(owner: owner, hotkey: hotkey))
                }
            }
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
