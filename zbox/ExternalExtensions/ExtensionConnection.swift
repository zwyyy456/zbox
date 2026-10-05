import Foundation
import Darwin

actor ExtensionConnection {
    private var outgoing = Data()
    private var running = false

    func send(_ message: ExtensionMessage) throws {
        guard running else { throw ExtensionFailure("The extension connection is closed.") }
        var data = try JSONEncoder().encode(message)
        guard data.count <= ExtensionFrameDecoder.limit, outgoing.count + data.count < 16 * 1024 * 1024 else {
            throw ExtensionFailure("The extension is not consuming protocol messages.")
        }
        data.append(10); outgoing.append(data)
    }

    func run(_ invocation: ScriptInvocation, initial: ExtensionMessage,
             receive: @escaping @Sendable (ExtensionMessage) async throws -> Void) async throws -> ScriptRunResult {
        try Task.checkCancellation()
        let child = try ChildProcess.start(invocation, interactive: true)
        running = true
        defer { running = false; outgoing.removeAll(); child.close() }
        let clock = ContinuousClock()
        var decoder = ExtensionFrameDecoder()
        var stderr = Data(), truncated = false
        var stoppingAt: ContinuousClock.Instant?
        var failure: (any Error)?
        var exited = false
        var status: Int32 = 0
        do { try send(initial) } catch { failure = error }
        while true {
            var info = siginfo_t()
            if waitid(P_PID, id_t(child.pid), &info, WEXITED | WNOHANG | WNOWAIT) == 0, info.si_pid == child.pid { exited = true }
            if stoppingAt == nil && (Task.isCancelled || failure != nil || exited) {
                stoppingAt = clock.now
                kill(-child.pid, SIGTERM)
            }
            var outputDrained = false, errorDrained = false
            var buffer = [UInt8](repeating: 0, count: 8192)
            for (fd, isError) in [(child.output.fileDescriptor, false), (child.error.fileDescriptor, true)] {
                for _ in 0..<8 {
                    let count = read(fd, &buffer, buffer.count)
                    guard count > 0 else {
                        if isError { errorDrained = true } else { outputDrained = true }
                        if count == 0 && !isError && !exited && stoppingAt == nil { failure = ExtensionFailure("The extension output pipe closed.") }
                        break
                    }
                    if isError {
                        let remaining = max(0, ScriptRunner.outputLimit - stderr.count)
                        stderr.append(contentsOf: buffer.prefix(min(count, remaining)))
                        truncated = truncated || count > remaining
                    } else if failure == nil && !Task.isCancelled {
                        do {
                            for message in try decoder.append(Data(buffer.prefix(count))) { try await receive(message) }
                        } catch { failure = error }
                    }
                }
            }
            if stoppingAt == nil, !outgoing.isEmpty, let input = child.input {
                let count = outgoing.withUnsafeBytes { write(input.fileDescriptor, $0.baseAddress, min($0.count, 65536)) }
                if count > 0 { outgoing.removeFirst(count) }
                else if count < 0 && errno != EAGAIN && errno != EINTR { failure = ExtensionFailure("The extension input pipe closed.") }
            }
            if let stoppingAt, (exited && outputDrained && errorDrained) || clock.now - stoppingAt >= .seconds(2) {
                kill(-child.pid, SIGKILL)
                while waitpid(child.pid, &status, 0) < 0 && errno == EINTR {}
                break
            }
            // Cancellation still needs a non-cancelling wait while the process group is reaped.
            await withCheckedContinuation { continuation in
                DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(10)) { continuation.resume() }
            }
        }
        if let failure { throw failure }
        if !Task.isCancelled && decoder.hasPartialFrame { throw ExtensionFailure("The extension exited with an incomplete message.") }
        return ScriptRunResult(output: ScriptOutput(stdout: Data(), stderr: stderr, truncated: truncated), status: status,
                               cancelled: Task.isCancelled, timedOut: false)
    }
}
