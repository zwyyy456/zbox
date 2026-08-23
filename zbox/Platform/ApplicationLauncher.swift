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
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        do {
            _ = try await NSWorkspace.shared.openApplication(
                at: application.url,
                configuration: configuration
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ApplicationLaunchError.unableToOpen(application.name)
        }
    }
}
