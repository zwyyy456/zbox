import Foundation
import Testing
@testable import zbox

struct ExtensionConnectionTests {
    @Test func framesSurvivePartialReadsAndRejectInvalidEnvelopes() throws {
        var decoder = ExtensionFrameDecoder()
        #expect(try decoder.append(Data("{\"jsonrpc\":\"2.0\",\"id\":\"1\",".utf8)).isEmpty)
        let messages = try decoder.append(Data("\"result\":null}\n{\"jsonrpc\":\"2.0\",\"method\":\"ui\"}\n".utf8))
        #expect(messages.count == 2)
        #expect(messages[0].result == .null)
        #expect(!decoder.hasPartialFrame)
        #expect(throws: (any Error).self) { try decoder.append(Data("{\"jsonrpc\":\"2.0\",\"id\":\"2\"}\n".utf8)) }
    }

    @Test func duplexConnectionCancelsAndReapsChildGroup() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let script = root.appending(path: "main.zsh")
        try """
        read -r initial
        (while true; do print x >> heartbeat; /bin/sleep 0.05; done) &
        print -r -- '{"jsonrpc":"2.0","id":"initialize","result":{"protocolVersion":1}}'
        read -r next
        print -r -- '{"jsonrpc":"2.0","method":"received"}'
        wait
        """.write(to: script, atomically: true, encoding: .utf8)
        let connection = ExtensionConnection()
        let (events, continuation) = AsyncStream<String>.makeStream()
        let task = Task {
            try await connection.run(ScriptInvocation(executable: "/bin/zsh", arguments: ["-f", script.path], directory: root.path, timeout: 5),
                                     initial: ExtensionMessage(id: "initialize", method: "initialize")) { message in
                continuation.yield(message.method ?? message.id ?? "")
            }
        }
        let deadline = Task { try await Task.sleep(for: .seconds(5)); task.cancel(); continuation.finish() }
        defer { deadline.cancel(); continuation.finish() }
        var received = false
        for await event in events {
            if event == "initialize" { try await connection.send(ExtensionMessage(method: "start")) }
            if event == "received" { received = true; task.cancel(); break }
        }
        let result = try await task.value
        #expect(received && result.cancelled)
        let heartbeat = root.appending(path: "heartbeat")
        let before = try Data(contentsOf: heartbeat)
        try await Task.sleep(for: .milliseconds(150))
        #expect(try Data(contentsOf: heartbeat) == before)
    }
}
