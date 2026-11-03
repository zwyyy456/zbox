import Foundation

nonisolated enum CommandRegistryError: Error, Equatable {
    case duplicateID(CommandID)
    case unknownID(CommandID)
}

@MainActor
final class CommandRegistry {
    typealias Performer = @MainActor (CommandContext) async throws -> Void

    private struct Entry {
        let descriptor: CommandDescriptor
        let perform: Performer
    }

    private var entries: [CommandID: Entry] = [:]
    private var orderedIDs: [CommandID] = []

    var descriptors: [CommandDescriptor] {
        orderedIDs.compactMap { entries[$0]?.descriptor }
    }

    func register(
        _ descriptor: CommandDescriptor,
        perform: @escaping Performer
    ) throws {
        guard entries[descriptor.id] == nil else {
            throw CommandRegistryError.duplicateID(descriptor.id)
        }

        entries[descriptor.id] = Entry(descriptor: descriptor, perform: perform)
        orderedIDs.append(descriptor.id)
    }

    func execute(_ id: CommandID, context: CommandContext) async throws {
        guard let entry = entries[id] else {
            throw CommandRegistryError.unknownID(id)
        }
        try await entry.perform(context)
    }
}
