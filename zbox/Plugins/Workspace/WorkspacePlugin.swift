import Foundation
import Observation

@MainActor
@Observable
final class WorkspacePlugin {
    static let captureCommandID = CommandID("workspace.capture")
    static let manageCommandID = CommandID("workspace.manage")
    private let defaults: UserDefaults
    let store: WorkspaceStore
    private(set) var isEnabled: Bool
    var capture: WorkspaceCapture?
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

    func prepareCapture(replacing: WorkspaceLayout? = nil) throws {
        guard isEnabled else { throw WorkspaceError.disabled }
        capture = try WorkspaceWindowAccess.capture(replacing: replacing)
    }

    func register(in registry: CommandRegistry, openSettings: @escaping @MainActor () throws -> Void) throws {
        try registry.register(CommandDescriptor(id: Self.captureCommandID,
            title: String(localized: "Save Current Workspace"), subtitle: nil,
            keywords: ["workspace", "save", "保存工作区", "布局"])) { [weak self] _ in
            guard let self else { return }
            guard isEnabled else { try openSettings(); return }
            try prepareCapture()
            try openSettings()
        }
        try registry.register(CommandDescriptor(id: Self.manageCommandID,
            title: String(localized: "Manage Workspaces"), subtitle: nil,
            keywords: ["workspace", "layout", "工作区", "布局"])) { _ in
            try openSettings()
        }
    }
}
