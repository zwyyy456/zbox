import Foundation
import Observation

nonisolated struct WorkspaceLayout: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var entries: [WorkspaceEntry]
    var foregroundBundleID: String?

    var commandID: CommandID { CommandID("workspace.\(id.uuidString)") }
}

nonisolated struct WorkspaceEntry: Codable, Identifiable, Equatable, Sendable {
    var id: String { bundleID }
    let bundleID: String
    let applicationName: String
    let applicationURL: URL
    let displayID: String
    let displayName: String
    let frame: CGRect
}

@MainActor
@Observable
final class WorkspaceStore {
    private let defaults: UserDefaults
    private static let key = "workspace.layouts"
    private(set) var layouts: [WorkspaceLayout] = []
    private(set) var errorMessage: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let data = defaults.data(forKey: Self.key) else { return }
        do {
            layouts = try JSONDecoder().decode([WorkspaceLayout].self, from: data)
        } catch {
            errorMessage = String(localized: "Saved workspaces could not be read. Your stored data has been preserved.")
        }
    }

    func save(_ layout: WorkspaceLayout) throws {
        var updated = layouts
        if let index = updated.firstIndex(where: { $0.id == layout.id }) {
            updated[index] = layout
        } else {
            updated.append(layout)
        }
        try persist(updated)
    }

    func delete(_ id: UUID) throws {
        try persist(layouts.filter { $0.id != id })
    }

    private func persist(_ updated: [WorkspaceLayout]) throws {
        guard errorMessage == nil else { throw WorkspaceError.unreadableData }
        let data = try JSONEncoder().encode(updated)
        defaults.set(data, forKey: Self.key)
        layouts = updated
    }
}

nonisolated enum WorkspaceError: LocalizedError {
    case disabled, unreadableData

    var errorDescription: String? {
        switch self {
        case .disabled: String(localized: "Enable Workspace in Settings first.")
        case .unreadableData: String(localized: "Saved workspaces could not be read. Your stored data has been preserved.")
        }
    }
}
