import Foundation
import Observation

nonisolated struct DisplayPreset: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name: String
    let selections: [DisplaySelection]
    var commandID: CommandID { CommandID("display.preset.\(id.uuidString)") }
}

@MainActor
@Observable
final class DisplayPresetStore {
    private let defaults: UserDefaults
    private static let key = "display.presets"
    private(set) var presets: [DisplayPreset] = []
    private(set) var errorMessage: String?

    init(defaults: UserDefaults) {
        self.defaults = defaults
        guard let data = defaults.data(forKey: Self.key) else { return }
        do { presets = try JSONDecoder().decode([DisplayPreset].self, from: data) }
        catch { errorMessage = String(localized: "Saved display presets could not be read. The original data was preserved.") }
    }

    func save(_ preset: DisplayPreset) throws {
        var updated = presets
        if let index = updated.firstIndex(where: { $0.id == preset.id }) { updated[index] = preset }
        else { updated.append(preset) }
        try persist(updated)
    }

    func delete(_ id: UUID) throws { try persist(presets.filter { $0.id != id }) }

    private func persist(_ updated: [DisplayPreset]) throws {
        guard errorMessage == nil else { throw DisplayPresetError.unreadable }
        defaults.set(try JSONEncoder().encode(updated), forKey: Self.key)
        presets = updated
    }
}

nonisolated enum DisplayPresetError: LocalizedError {
    case unreadable
    var errorDescription: String? {
        String(localized: "Saved display presets could not be read. The original data was preserved.")
    }
}
