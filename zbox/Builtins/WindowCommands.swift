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
    static let leftHalfID = CommandID("window.left-half")
    static let rightHalfID = CommandID("window.right-half")
    static let maximizeID = CommandID("window.maximize")
    static let shortcutTargets = [
        CommandShortcutTarget(id: leftHalfID, title: String(localized: "Left Half")),
        CommandShortcutTarget(id: rightHalfID, title: String(localized: "Right Half")),
        CommandShortcutTarget(id: maximizeID, title: String(localized: "Maximize")),
    ]

    @MainActor
    static func registerAll(
        in registry: CommandRegistry,
        controller: AccessibilityWindowController,
        isEnabled: @escaping @MainActor () -> Bool
    ) throws {
        try register(
            id: leftHalfID,
            title: String(localized: "Left Half"),
            keywords: ["window", "left", "resize", "tile", "窗口", "左半屏"],
            action: .leftHalf,
            in: registry,
            controller: controller,
            isEnabled: isEnabled
        )
        try register(
            id: rightHalfID,
            title: String(localized: "Right Half"),
            keywords: ["window", "right", "resize", "tile", "窗口", "右半屏"],
            action: .rightHalf,
            in: registry,
            controller: controller,
            isEnabled: isEnabled
        )
        try register(
            id: maximizeID,
            title: String(localized: "Maximize"),
            keywords: ["window", "full", "resize", "zoom", "窗口", "最大化"],
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
            subtitle: String(localized: "Window Management"),
            keywords: keywords
        )
        try registry.register(descriptor) { context in
            guard isEnabled() else { throw WindowManagementError.disabled }
            try controller.perform(action, targetPID: context.frontmostApplicationPID)
        }
    }
}
