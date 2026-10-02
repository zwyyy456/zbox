import AppKit
import Observation

@MainActor @Observable
final class QuicklinksPlugin {
    static let commandID = CommandID("quicklinks.manage")
    private let defaults: UserDefaults
    let store = QuicklinkStore()
    private(set) var isEnabled: Bool
    var statusMessage: String?

    var shortcutTargets: [CommandShortcutTarget] {
        store.items.map { CommandShortcutTarget(id: $0.commandID, title: $0.name) }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: "quicklinks.enabled")
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: "quicklinks.enabled")
    }

    func register(in registry: CommandRegistry, openSettings: @escaping @MainActor () throws -> Void) throws {
        try registry.register(CommandDescriptor(id: Self.commandID, title: String(localized: "Quicklinks"),
            subtitle: nil, keywords: ["quicklinks", "links", "快捷入口", "链接"])) { _ in try openSettings() }
        guard isEnabled else { return }
        for item in store.items {
            try registry.register(CommandDescriptor(id: item.commandID, title: item.name,
                subtitle: String(localized: "Quicklinks"), keywords: item.keywords.components(separatedBy: .whitespacesAndNewlines))) { _ in
                let url = try item.destination()
                if url.isFileURL, !FileManager.default.fileExists(atPath: url.path) { throw QuicklinkError.missingFile }
                guard NSWorkspace.shared.open(url) else { throw QuicklinkError.openFailed }
            }
        }
    }
}
