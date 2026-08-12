import Foundation

enum WindowCommands {
    static let leftHalfID = CommandID("window.left-half")
    static let rightHalfID = CommandID("window.right-half")
    static let maximizeID = CommandID("window.maximize")

    @MainActor
    static func registerAll(
        in registry: CommandRegistry,
        controller: AccessibilityWindowController
    ) throws {
        try register(
            id: leftHalfID,
            title: "Left Half",
            keywords: ["window", "left", "resize", "tile"],
            action: .leftHalf,
            in: registry,
            controller: controller
        )
        try register(
            id: rightHalfID,
            title: "Right Half",
            keywords: ["window", "right", "resize", "tile"],
            action: .rightHalf,
            in: registry,
            controller: controller
        )
        try register(
            id: maximizeID,
            title: "Maximize",
            keywords: ["window", "full", "resize", "zoom"],
            action: .maximize,
            in: registry,
            controller: controller
        )
    }

    static func systemImage(for commandID: CommandID) -> String? {
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
        controller: AccessibilityWindowController
    ) throws {
        let descriptor = CommandDescriptor(
            id: id,
            title: title,
            subtitle: "Window Management",
            keywords: keywords
        )
        try registry.register(descriptor) { context in
            try controller.perform(action, targetPID: context.frontmostApplicationPID)
        }
    }
}
