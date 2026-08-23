import Foundation

nonisolated struct CommandShortcutTarget: Identifiable, Sendable {
    let id: CommandID
    let title: String
}

nonisolated enum WindowManagementError: LocalizedError, Equatable {
    case disabled

    var errorDescription: String? {
        "Enable Window Management in Settings before running this command."
    }
}

nonisolated enum WindowCommands {
    static let leftHalfID = CommandID("window.left-half")
    static let rightHalfID = CommandID("window.right-half")
    static let maximizeID = CommandID("window.maximize")
    static let shortcutTargets = [
        CommandShortcutTarget(id: leftHalfID, title: "Left Half"),
        CommandShortcutTarget(id: rightHalfID, title: "Right Half"),
        CommandShortcutTarget(id: maximizeID, title: "Maximize"),
    ]

    @MainActor
    static func registerAll(
        in registry: CommandRegistry,
        controller: AccessibilityWindowController,
        isEnabled: @escaping @MainActor () -> Bool
    ) throws {
        try register(
            id: leftHalfID,
            title: "Left Half",
            keywords: ["window", "left", "resize", "tile"],
            action: .leftHalf,
            in: registry,
            controller: controller,
            isEnabled: isEnabled
        )
        try register(
            id: rightHalfID,
            title: "Right Half",
            keywords: ["window", "right", "resize", "tile"],
            action: .rightHalf,
            in: registry,
            controller: controller,
            isEnabled: isEnabled
        )
        try register(
            id: maximizeID,
            title: "Maximize",
            keywords: ["window", "full", "resize", "zoom"],
            action: .maximize,
            in: registry,
            controller: controller,
            isEnabled: isEnabled
        )
    }

    nonisolated static func systemImage(for commandID: CommandID) -> String? {
        switch commandID {
        case leftHalfID:
            "rectangle.lefthalf.inset.filled"
        case rightHalfID:
            "rectangle.righthalf.inset.filled"
        case maximizeID:
            "rectangle.inset.filled"
        default:
            nil
        }
    }

    @MainActor
    private static func register(
        id: CommandID,
        title: String,
        keywords: [String],
        action: WindowAction,
        in registry: CommandRegistry,
        controller: AccessibilityWindowController,
        isEnabled: @escaping @MainActor () -> Bool
    ) throws {
        let descriptor = CommandDescriptor(
            id: id,
            title: title,
            subtitle: "Window Management",
            keywords: keywords
        )
        try registry.register(descriptor) { context in
            guard isEnabled() else { throw WindowManagementError.disabled }
            try controller.perform(action, targetPID: context.frontmostApplicationPID)
        }
    }
}
