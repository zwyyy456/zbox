nonisolated enum SettingsCommands {
    static let openID = CommandID("settings.open")

    @MainActor
    static func register(
        in registry: CommandRegistry,
        openSettings: @escaping @MainActor () throws -> Void
    ) throws {
        let descriptor = CommandDescriptor(
            id: openID,
            title: "Settings",
            subtitle: "ZBox Settings",
            keywords: ["settings", "preferences", "configuration"]
        )
        try registry.register(descriptor) { _ in
            try openSettings()
        }
    }

    nonisolated static func systemImage(for commandID: CommandID) -> String? {
        commandID == openID ? "gearshape" : nil
    }
}
