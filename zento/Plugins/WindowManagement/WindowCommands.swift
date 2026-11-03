import Foundation

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
        Definition(id: CommandID("window.left-half"), title: String(localized: "Move to Left Half"),
                   keywords: ["window", "窗口", "left", "左半屏"],
                   action: .leftHalf, systemImage: "rectangle.lefthalf.inset.filled"),
        Definition(id: CommandID("window.right-half"), title: String(localized: "Move to Right Half"),
                   keywords: ["window", "窗口", "right", "右半屏"],
                   action: .rightHalf, systemImage: "rectangle.righthalf.inset.filled"),
        Definition(id: CommandID("window.maximize"), title: String(localized: "Maximize Window"),
                   keywords: ["window", "窗口", "maximize", "最大化"],
                   action: .maximize, systemImage: "rectangle.inset.filled"),
        Definition(id: CommandID("window.top-half"), title: String(localized: "Move to Top Half"),
                   keywords: ["window", "窗口", "top", "上半屏"],
                   action: .topHalf, systemImage: "rectangle.tophalf.inset.filled"),
        Definition(id: CommandID("window.bottom-half"), title: String(localized: "Move to Bottom Half"),
                   keywords: ["window", "窗口", "bottom", "下半屏"],
                   action: .bottomHalf, systemImage: "rectangle.bottomhalf.inset.filled"),
        Definition(id: CommandID("window.top-left-quarter"), title: String(localized: "Move to Top Left Quarter"),
                   keywords: ["window", "窗口", "top", "left", "quarter", "左上", "四分之一"],
                   action: .topLeftQuarter, systemImage: "rectangle.split.2x2"),
        Definition(id: CommandID("window.top-right-quarter"), title: String(localized: "Move to Top Right Quarter"),
                   keywords: ["window", "窗口", "top", "right", "quarter", "右上", "四分之一"],
                   action: .topRightQuarter, systemImage: "rectangle.split.2x2"),
        Definition(id: CommandID("window.bottom-left-quarter"), title: String(localized: "Move to Bottom Left Quarter"),
                   keywords: ["window", "窗口", "bottom", "left", "quarter", "左下", "四分之一"],
                   action: .bottomLeftQuarter, systemImage: "rectangle.split.2x2"),
        Definition(id: CommandID("window.bottom-right-quarter"), title: String(localized: "Move to Bottom Right Quarter"),
                   keywords: ["window", "窗口", "bottom", "right", "quarter", "右下", "四分之一"],
                   action: .bottomRightQuarter, systemImage: "rectangle.split.2x2"),
        Definition(id: CommandID("window.left-third"), title: String(localized: "Move to Left Third"),
                   keywords: ["window", "窗口", "left", "third", "左侧", "三分之一"],
                   action: .leftThird, systemImage: "rectangle.split.3x1"),
        Definition(id: CommandID("window.center-third"), title: String(localized: "Move to Center Third"),
                   keywords: ["window", "窗口", "center", "third", "中间", "三分之一"],
                   action: .centerThird, systemImage: "rectangle.split.3x1"),
        Definition(id: CommandID("window.right-third"), title: String(localized: "Move to Right Third"),
                   keywords: ["window", "窗口", "right", "third", "右侧", "三分之一"],
                   action: .rightThird, systemImage: "rectangle.split.3x1"),
        Definition(id: CommandID("window.left-two-thirds"), title: String(localized: "Move to Left Two Thirds"),
                   keywords: ["window", "窗口", "left", "two", "thirds", "左侧", "三分之二"],
                   action: .leftTwoThirds, systemImage: "rectangle.split.3x1"),
        Definition(id: CommandID("window.right-two-thirds"), title: String(localized: "Move to Right Two Thirds"),
                   keywords: ["window", "窗口", "right", "two", "thirds", "右侧", "三分之二"],
                   action: .rightTwoThirds, systemImage: "rectangle.split.3x1"),
        Definition(id: CommandID("window.center"), title: String(localized: "Center Window"),
                   keywords: ["window", "窗口", "center", "居中"],
                   action: .center, systemImage: "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left"),
        Definition(id: CommandID("window.restore"), title: String(localized: "Restore Previous Window Frame"),
                   keywords: ["window", "窗口", "restore", "undo", "恢复", "还原", "撤销"],
                   action: .restore, systemImage: "arrow.uturn.backward"),
        Definition(id: CommandID("window.previous-display"), title: String(localized: "Move to Previous Display"),
                   keywords: ["window", "窗口", "previous", "display", "monitor", "上一", "显示器", "屏幕"],
                   action: .previousDisplay, systemImage: "display.2"),
        Definition(id: CommandID("window.next-display"), title: String(localized: "Move to Next Display"),
                   keywords: ["window", "窗口", "next", "display", "monitor", "下一", "显示器", "屏幕"],
                   action: .nextDisplay, systemImage: "display.2"),
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
            let descriptor = CommandDescriptor(systemImage: definition.systemImage,
                id: definition.id,
                title: definition.title,
                category: String(localized: "Window Management"),
                subtitle: nil,
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

}
