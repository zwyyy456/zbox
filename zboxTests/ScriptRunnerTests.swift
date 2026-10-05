import Foundation
import Testing
@testable import zbox

struct ScriptRunnerTests {
    private func invocation(_ source: String, timeout: Double = 5) throws -> (URL, ScriptInvocation) {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = directory.appending(path: "test.zsh")
        try source.write(to: script, atomically: true, encoding: .utf8)
        return (directory, ScriptInvocation(executable: "/bin/zsh", arguments: ["-f", script.path], directory: directory.path, timeout: timeout))
    }

    @Test func drainsBothStreamsAndReportsExit() async throws {
        let (directory, command) = try invocation("""
        /usr/bin/head -c 1200000 /dev/zero
        /usr/bin/head -c 1200000 /dev/zero >&2
        exit 7
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let result = try await ScriptRunner.run(command) { _ in }
        #expect(result.status >> 8 == 7)
        #expect(result.output.stdout.count == ScriptRunner.outputLimit)
        #expect(result.output.stderr.count == ScriptRunner.outputLimit)
        #expect(result.output.truncated)
        #expect(!result.timedOut && !result.cancelled)
    }

    @Test(arguments: [false, true]) func stopsProcessGroup(cancel: Bool) async throws {
        let (directory, command) = try invocation("""
        (while true; do print x >> heartbeat; /bin/sleep 0.05; done) &
        print ready
        wait
        """, timeout: cancel ? 10 : 1)
        defer { try? FileManager.default.removeItem(at: directory) }
        let (updates, continuation) = AsyncStream<Void>.makeStream()
        let task = Task {
            try await ScriptRunner.run(command) { output in
                if !output.stdout.isEmpty { continuation.yield(()) }
            }
        }
        if cancel {
            for await _ in updates { task.cancel(); break }
        }
        let result = try await task.value
        continuation.finish()
        #expect(result.cancelled == cancel)
        #expect(result.timedOut == !cancel)
        let heartbeat = directory.appending(path: "heartbeat")
        let before = try Data(contentsOf: heartbeat)
        try await Task.sleep(for: .milliseconds(150))
        #expect(try Data(contentsOf: heartbeat) == before)
    }
}
