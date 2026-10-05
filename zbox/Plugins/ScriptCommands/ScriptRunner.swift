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
        let out = Pipe(), err = Pipe()
        defer {
            try? out.fileHandleForReading.close()
            try? err.fileHandleForReading.close()
        }
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        posix_spawn_file_actions_init(&actions)
        posix_spawnattr_init(&attributes)
        defer {
            posix_spawn_file_actions_destroy(&actions)
            posix_spawnattr_destroy(&attributes)
        }
        // Each run owns a process group so stopping it also reaches ordinary child processes.
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT))
        posix_spawnattr_setpgroup(&attributes, 0)
        guard posix_spawn_file_actions_addchdir_np(&actions, invocation.directory) == 0,
              posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0) == 0,
              posix_spawn_file_actions_adddup2(&actions, out.fileHandleForWriting.fileDescriptor, STDOUT_FILENO) == 0,
              posix_spawn_file_actions_adddup2(&actions, err.fileHandleForWriting.fileDescriptor, STDERR_FILENO) == 0 else {
            throw ScriptCommandError.launchFailed
        }
        let environment = [
            "HOME=\(NSHomeDirectory())", "USER=\(NSUserName())", "TMPDIR=\(NSTemporaryDirectory())",
            "LANG=en_US.UTF-8", "PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        ]
        let argv = ([invocation.executable] + invocation.arguments).map { strdup($0) } + [nil]
        let envp = environment.map { strdup($0) } + [nil]
        defer { for pointer in argv + envp { free(pointer) } }
        var pid: pid_t = 0
        let launched = argv.withUnsafeBufferPointer { arguments in
            envp.withUnsafeBufferPointer { environment in
                posix_spawn(&pid, invocation.executable, &actions, &attributes, arguments.baseAddress!, environment.baseAddress!)
            }
        }
        try? out.fileHandleForWriting.close()
        try? err.fileHandleForWriting.close()
        guard launched == 0 else { throw ScriptCommandError.launchFailed }
        let outFD = out.fileHandleForReading.fileDescriptor, errFD = err.fileHandleForReading.fileDescriptor
        _ = fcntl(outFD, F_SETFL, O_NONBLOCK)
        _ = fcntl(errFD, F_SETFL, O_NONBLOCK)
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
