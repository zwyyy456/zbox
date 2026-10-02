import Foundation
import Observation

@MainActor
@Observable
final class WorkspacePlugin {
    static let manageCommandID = CommandID("workspace.manage")
    private let defaults: UserDefaults
    let store: WorkspaceStore
    private(set) var isEnabled: Bool
    var selectedLayoutID: UUID?
    var statusMessage: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        store = WorkspaceStore(defaults: defaults)
        isEnabled = defaults.bool(forKey: "workspace.enabled")
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: "workspace.enabled")
    }

    func register(in registry: CommandRegistry, openSettings: @escaping @MainActor () throws -> Void) throws {
        try registry.register(CommandDescriptor(id: Self.manageCommandID,
            title: String(localized: "Manage Workspaces"), subtitle: nil,
            keywords: ["workspace", "layout", "工作区", "布局"])) { _ in
            try openSettings()
        }
    }
}
