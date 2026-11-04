import Foundation

enum ApplicationCommands {
    /// Includes saved aliases for applications that are temporarily absent from the catalog.
    static func owns(_ id: CommandID) -> Bool {
        id.rawValue.hasPrefix("application.")
    }

    static func id(for application: ApplicationInfo) -> CommandID {
        if let bundleIdentifier = application.bundleIdentifier {
            return CommandID("application.\(bundleIdentifier.lowercased())")
        }
        return CommandID("application.url.\(application.url.standardizedFileURL.path)")
    }

    @MainActor
    static func register(
        _ application: ApplicationInfo,
        in registry: CommandRegistry,
        launcher: ApplicationLauncher
    ) throws {
        let descriptor = CommandDescriptor(
            id: id(for: application),
            title: application.name,
            subtitle: application.url.path,
            keywords: [application.bundleIdentifier, application.url.lastPathComponent]
                .compactMap { $0 },
            searchAliases: ApplicationSearchAliases.make(for: application.name)
        )

        try registry.register(descriptor) { _ in
            try await launcher.launch(application)
        }
    }
}
