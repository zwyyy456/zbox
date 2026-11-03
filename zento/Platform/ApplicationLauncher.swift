import AppKit

enum ApplicationLaunchError: LocalizedError {
    case unableToOpen(String)

    var errorDescription: String? {
        switch self {
        case .unableToOpen(let name):
            String(localized: "Unable to open \(name).")
        }
    }
}

@MainActor
struct ApplicationLauncher {
    func launch(_ application: ApplicationInfo) async throws {
        do {
            _ = try await open(at: application.url, activates: true)
        } catch is CancellationError { throw CancellationError() }
        catch { throw ApplicationLaunchError.unableToOpen(application.name) }
    }

    func open(at url: URL, activates: Bool) async throws -> NSRunningApplication {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = activates
        return try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }
}
