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
    var displayMapping: WorkspaceDisplayMapping?
    private(set) var isRestoring = false
    private(set) var results: [WorkspaceRestoreResult] = []
    private(set) var restoringName: String?
    @ObservationIgnored private var restoreTask: Task<Void, Never>?
    private var runID: UUID?
    @ObservationIgnored var onCompletion: ((String?, Bool) -> Void)?

    var shortcutTargets: [CommandShortcutTarget] {
        store.layouts.map { CommandShortcutTarget(id: $0.commandID, title: String(localized: "Restore Workspace: \($0.name)")) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        store = WorkspaceStore(defaults: defaults)
        isEnabled = defaults.bool(forKey: "workspace.enabled")
    }

    func setEnabled(_ enabled: Bool) {
        if !enabled { stop() }
        isEnabled = enabled
        defaults.set(enabled, forKey: "workspace.enabled")
    }

    func stop() {
        restoreTask?.cancel()
        restoreTask = nil
        runID = nil
        isRestoring = false
        capture = nil
        displayMapping = nil
    }

    func cancelRestore() {
        stop()
        statusMessage = String(localized: "Restoration cancelled. Completed changes were kept.")
    }

    func prepareRestore(_ layout: WorkspaceLayout) throws -> Bool {
        guard isEnabled else { throw WorkspaceError.disabled }
        guard AccessibilityAuthorization().isTrusted else { throw AccessibilityWindowError.permissionRequired }
        guard !isRestoring, displayMapping == nil else { throw WorkspaceRestoreError.busy }
        let displays = WorkspaceDisplay.current()
        var seen = Set<String>()
        let missing = layout.entries.filter { entry in
            WorkspaceDisplay.matching(entry.displayID, in: displays) == nil && seen.insert(entry.displayID).inserted
        }
        if !missing.isEmpty {
            displayMapping = WorkspaceDisplayMapping(layout: layout, missing: missing, displays: displays)
            return true
        }
        restore(layout, mapping: [:])
        return false
    }

    func restore(_ layout: WorkspaceLayout, mapping: [String: String]) {
        guard isEnabled, !isRestoring else { return }
        displayMapping = nil
        isRestoring = true
        restoringName = layout.name
        results = []
        statusMessage = nil
        let id = UUID()
        runID = id
        restoreTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if runID == id { isRestoring = false; restoreTask = nil; runID = nil }
            }
            do {
                try await WorkspaceRestorer().restore(layout, mapping: mapping) { result in
                    if runID == id { results.append(result) }
                }
                try Task.checkCancellation()
                guard runID == id else { return }
                let count = results.filter(\.succeeded).count
                let summary = String(localized: "Restored \(count) of \(layout.entries.count) applications.")
                statusMessage = summary
                onCompletion?(count == layout.entries.count ? nil : summary, false)
            } catch is CancellationError {
                return
            } catch {
                guard runID == id else { return }
                statusMessage = error.localizedDescription
                onCompletion?(error.localizedDescription, error as? AccessibilityWindowError == .permissionRequired)
            }
        }
    }

    func prepareCapture(replacing: WorkspaceLayout? = nil) throws {
        guard isEnabled else { throw WorkspaceError.disabled }
        guard !isRestoring else { throw WorkspaceRestoreError.busy }
        statusMessage = nil
        capture = try WorkspaceWindowAccess.capture(replacing: replacing)
    }

    func register(in registry: CommandRegistry, openSettings: @escaping @MainActor () throws -> Void) throws {
        for layout in store.layouts {
            try registry.register(CommandDescriptor(id: layout.commandID,
                title: String(localized: "Restore Workspace: \(layout.name)"),
                subtitle: layout.entries.map(\.applicationName).joined(separator: ", "),
                keywords: ["workspace", "restore", "工作区", "恢复", layout.name])) { [weak self] _ in
                guard let self else { return }
                guard isEnabled else { try openSettings(); return }
                if try prepareRestore(layout) {
                    do { try openSettings() }
                    catch { displayMapping = nil; throw error }
                }
            }
        }
        try registry.register(CommandDescriptor(id: Self.captureCommandID,
            title: String(localized: "Save Current Workspace"), subtitle: nil,
            keywords: ["workspace", "save", "保存工作区", "布局"])) { [weak self] _ in
            guard let self else { return }
            guard isEnabled else { try openSettings(); return }
            try prepareCapture()
            do { try openSettings() }
            catch { capture = nil; throw error }
        }
        try registry.register(CommandDescriptor(id: Self.manageCommandID,
            title: String(localized: "Manage Workspaces"), subtitle: nil,
            keywords: ["workspace", "layout", "工作区", "布局"])) { _ in
            try openSettings()
        }
    }
}
