import AppKit
import Observation

@MainActor
@Observable
final class AppEnvironment {
    private let applicationCatalog = ApplicationCatalog()
    private let applicationLauncher = ApplicationLauncher()
    private let hotkeyRegistrar = GlobalHotkeyRegistrar()
    private let windowController = AccessibilityWindowController()

    private(set) var applications: [ApplicationInfo] = []
    private(set) var targetApplicationPID: pid_t?
    var searchQuery = ""
    var statusMessage = "Ready"

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
        searchPanelController.show()
    }

    func hideRootSearch() {
        searchPanelController.hide()
    }

    func reloadApplications() {
        applications = applicationCatalog.loadApplications()
        statusMessage = "Loaded \(applications.count) applications"
    }

    func launch(_ application: ApplicationInfo) {
        launchTask?.cancel()
        launchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await applicationLauncher.launch(application)
                statusMessage = "Opened \(application.name)"
            } catch is CancellationError {
                return
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    func launchFirstMatchingApplication() {
        let application = applications.first {
            searchQuery.isEmpty || $0.name.localizedCaseInsensitiveContains(searchQuery)
        }
        guard let application else { return }
        launch(application)
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
