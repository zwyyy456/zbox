import Foundation
import Observation

@MainActor @Observable
final class CommandAliasStore {
    private(set) var aliases: [CommandID: String]
    private let defaults: UserDefaults
    private static let key = "command.aliases"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        aliases = (defaults.dictionary(forKey: Self.key) as? [String: String] ?? [:])
            .reduce(into: [:]) { $0[CommandID($1.key)] = $1.value }
    }

    func validate(_ input: String, for id: CommandID) throws {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.unicodeScalars.contains(where: {
            CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0)
        }) else { throw AliasError.invalid }
        if !value.isEmpty, let conflict = aliases.first(where: {
            $0.key != id && SearchEngine.normalize($0.value) == SearchEngine.normalize(value)
        }) {
            throw AliasError.conflict(conflict.key)
        }
    }

    func set(_ input: String, for id: CommandID) throws {
        try validate(input, for: id)
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        aliases[id] = value.isEmpty ? nil : value
        persist()
    }

    func remove(_ id: CommandID) {
        aliases[id] = nil
        persist()
    }

    private func persist() {
        defaults.set(Dictionary(uniqueKeysWithValues: aliases.map { ($0.key.rawValue, $0.value) }), forKey: Self.key)
    }

    enum AliasError: Error {
        case invalid
        case conflict(CommandID)
    }
}
