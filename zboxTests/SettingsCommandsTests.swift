import Foundation
import Testing
@testable import zbox

@MainActor
struct SettingsCommandsTests {
    @Test
    func registersAndExecutesTheSettingsCommand() async throws {
        let registry = CommandRegistry()
        var didOpen = false

        try SettingsCommands.register(in: registry) {
            didOpen = true
        }

        let descriptor = try #require(
            registry.descriptors.first { $0.id == SettingsCommands.openID }
        )

        try await registry.execute(
            descriptor.id,
            context: CommandContext(source: .rootSearch, frontmostApplicationPID: nil)
        )
        #expect(didOpen)
    }
}
