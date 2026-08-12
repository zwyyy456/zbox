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

    private var commandRegistry = CommandRegistry()
    private var applicationURLsByCommandID: [CommandID: URL] = [:]
    private(set) var applications: [ApplicationInfo] = []
    private(set) var targetApplicationPID: pid_t?
    private(set) var selectedCommandID: CommandID?
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

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        reloadApplications()

        do {
            try hotkeyRegistrar.registerDefault { [weak self] in
                self?.toggleRootSearch()
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func stop() {
        launchTask?.cancel()
        hotkeyRegistrar.unregister()
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

        let registry = commandRegistry
        let context = CommandContext(
            source: .rootSearch,
            frontmostApplicationPID: targetApplicationPID
        )

        launchTask?.cancel()
        launchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await registry.execute(commandID, context: context)
                statusMessage = "Ran \(descriptor.title)"
                hideRootSearch()
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

    func performWindowAction(_ action: WindowAction) {
        do {
            try windowController.perform(action, targetPID: targetApplicationPID)
            statusMessage = "Window action completed"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func requestAccessibilityPermission() {
        windowController.requestPermission()
    }

    func openAccessibilitySettings() {
        windowController.openSystemSettings()
    }
}
