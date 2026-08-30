import Foundation

nonisolated struct CommandShortcutTarget: Identifiable, Sendable {
    let id: CommandID
    let title: String
}

nonisolated enum WindowManagementError: LocalizedError, Equatable {
    case disabled

    var errorDescription: String? {
        String(localized: "Enable Window Management in Settings before running this command.")
    }
}

nonisolated enum WindowCommands {
    private struct Definition {
        let id: CommandID
        let title: String
        let keywords: [String]
        let action: WindowAction
        let systemImage: String
    }

    static let leftHalfID = CommandID("window.left-half")
    static let rightHalfID = CommandID("window.right-half")
    static let maximizeID = CommandID("window.maximize")
    private static let definitions = [
        Definition(
            id: leftHalfID,
            title: String(localized: "Left Half"),
            keywords: ["window", "left", "resize", "tile", "窗口", "左半屏"],
            action: .leftHalf,
            systemImage: "rectangle.lefthalf.inset.filled"
        ),
        Definition(
            id: rightHalfID,
            title: String(localized: "Right Half"),
            keywords: ["window", "right", "resize", "tile", "窗口", "右半屏"],
            action: .rightHalf,
            systemImage: "rectangle.righthalf.inset.filled"
        ),
        Definition(
            id: maximizeID,
            title: String(localized: "Maximize"),
            keywords: ["window", "full", "resize", "zoom", "窗口", "最大化"],
            action: .maximize,
            systemImage: "rectangle.inset.filled"
        ),
    ]
    static let shortcutTargets = definitions.map {
        CommandShortcutTarget(id: $0.id, title: $0.title)
    }

    @MainActor
    static func registerAll(
        in registry: CommandRegistry,
        controller: AccessibilityWindowController,
        isEnabled: @escaping @MainActor () -> Bool
    ) throws {
        for definition in definitions {
            let descriptor = CommandDescriptor(
                id: definition.id,
                title: definition.title,
                subtitle: String(localized: "Window Management"),
                keywords: definition.keywords
            )
            try registry.register(descriptor) { context in
                guard isEnabled() else { throw WindowManagementError.disabled }
                try controller.perform(
                    definition.action,
                    targetPID: context.frontmostApplicationPID
                )
            }
        }
    }

    nonisolated static func systemImage(for commandID: CommandID) -> String? {
        definitions.first { $0.id == commandID }?.systemImage
    }
}
