import Testing
@testable import zbox

@MainActor
struct CommandRegistryTests {
    @Test
    func registersDescriptorsInOrderAndExecutesByID() async throws {
        let registry = CommandRegistry()
        let firstID = CommandID("test.first")
        let secondID = CommandID("test.second")
        var receivedContext: CommandContext?

        try registry.register(descriptor(id: firstID, title: "First")) { context in
            receivedContext = context
        }
        try registry.register(descriptor(id: secondID, title: "Second")) { _ in }

        #expect(registry.descriptors.map(\.id) == [firstID, secondID])

        try await registry.execute(
            firstID,
            context: CommandContext(source: .rootSearch, frontmostApplicationPID: 42)
        )
        #expect(receivedContext?.frontmostApplicationPID == 42)
    }

    @Test
    func rejectsDuplicateIDs() throws {
        let registry = CommandRegistry()
        let id = CommandID("test.duplicate")
        try registry.register(descriptor(id: id, title: "First")) { _ in }

        do {
            try registry.register(descriptor(id: id, title: "Second")) { _ in }
            Issue.record("Expected duplicate registration to fail")
        } catch {
            #expect(error as? CommandRegistryError == .duplicateID(id))
        }
    }

    @Test
    func rejectsUnknownIDs() async {
        let registry = CommandRegistry()
        let id = CommandID("test.missing")

        do {
            try await registry.execute(
                id,
                context: CommandContext(source: .rootSearch, frontmostApplicationPID: nil)
            )
            Issue.record("Expected unknown command execution to fail")
        } catch {
            #expect(error as? CommandRegistryError == .unknownID(id))
        }
    }

    private func descriptor(id: CommandID, title: String) -> CommandDescriptor {
        CommandDescriptor(id: id, title: title, subtitle: nil, keywords: [])
    }
}
