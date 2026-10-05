import Foundation
import Darwin

nonisolated struct ScriptOutput: Sendable {
    var stdout = Data()
    var stderr = Data()
    var truncated = false
}

nonisolated struct ScriptRunResult: Sendable {
    let output: ScriptOutput
    let status: Int32
    let cancelled: Bool
    let timedOut: Bool
}

nonisolated enum ScriptRunner {
    static let outputLimit = 1_048_576

    @concurrent static func run(_ invocation: ScriptInvocation,
        onOutput: @escaping @Sendable (ScriptOutput) async -> Void) async throws -> ScriptRunResult {
        try Task.checkCancellation()
        let child = try ChildProcess.start(invocation, interactive: false)
        defer { child.close() }
        let pid = child.pid, outFD = child.output.fileDescriptor, errFD = child.error.fileDescriptor
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(invocation.timeout))
        var stoppingAt: ContinuousClock.Instant?
        var cancelled = false, timedOut = false, exited = false
        var output = ScriptOutput()
        var lastPublish = clock.now
        var status: Int32 = 0
        while true {
            drain(outFD, into: &output.stdout, truncated: &output.truncated)
            drain(errFD, into: &output.stderr, truncated: &output.truncated)
            // Leave the child waitable until group cleanup, preventing its PID from being reused.
            var info = siginfo_t()
            if waitid(P_PID, id_t(pid), &info, WEXITED | WNOHANG | WNOWAIT) == 0, info.si_pid == pid { exited = true }
            if stoppingAt == nil {
                cancelled = Task.isCancelled
                timedOut = !cancelled && !exited && clock.now >= deadline
                if cancelled || timedOut || exited {
                    kill(-pid, SIGTERM)
                    stoppingAt = clock.now
                }
            }
            if let stoppingAt {
                // A normally completed script must not leave background jobs owned by zbox.
                if (exited && !cancelled && !timedOut) || clock.now - stoppingAt >= .seconds(2) {
                    kill(-pid, SIGKILL)
                    while waitpid(pid, &status, 0) < 0 && errno == EINTR {}
                    drain(outFD, into: &output.stdout, truncated: &output.truncated)
                    drain(errFD, into: &output.stderr, truncated: &output.truncated)
                    break
                }
            }
            if clock.now - lastPublish >= .milliseconds(100) {
                await onOutput(output)
                lastPublish = clock.now
            }
            // Cleanup must keep waiting after task cancellation rather than spinning on cancelled sleeps.
            await withCheckedContinuation { continuation in
                DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(20)) { continuation.resume() }
            }
        }
        await onOutput(output)
        return ScriptRunResult(output: output, status: status, cancelled: cancelled, timedOut: timedOut)
    }

    private static func drain(_ fd: Int32, into data: inout Data, truncated: inout Bool) {
        var buffer = [UInt8](repeating: 0, count: 8192)
        // Bound each pass so a busy stdout cannot starve stderr or cancellation.
        for _ in 0..<8 {
            let count = read(fd, &buffer, buffer.count)
            guard count > 0 else { return }
            let remaining = max(0, outputLimit - data.count)
            data.append(contentsOf: buffer.prefix(min(count, remaining)))
            if count > remaining { truncated = true }
        }
    }
}

nonisolated struct ScriptInvocation: Sendable {
    let executable: String
    let arguments: [String]
    let directory: String
    let timeout: Double
}

nonisolated enum ScriptProcessError: LocalizedError {
    case launchFailed
    var errorDescription: String? { String(localized: "The script process could not be started.") }
}
