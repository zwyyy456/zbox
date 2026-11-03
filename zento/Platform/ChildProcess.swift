import Foundation
import Darwin

nonisolated struct ChildProcess: Sendable {
    let pid: pid_t
    let input: FileHandle?
    let output: FileHandle
    let error: FileHandle

    static func start(_ invocation: ScriptInvocation, interactive: Bool) throws -> ChildProcess {
        let out = Pipe(), err = Pipe()
        let input = interactive ? Pipe() : nil
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
        let inputAction: Int32
        if let input { inputAction = posix_spawn_file_actions_adddup2(&actions, input.fileHandleForReading.fileDescriptor, STDIN_FILENO) }
        else { inputAction = posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0) }
        guard posix_spawn_file_actions_addchdir_np(&actions, invocation.directory) == 0,
              inputAction == 0,
              posix_spawn_file_actions_adddup2(&actions, out.fileHandleForWriting.fileDescriptor, STDOUT_FILENO) == 0,
              posix_spawn_file_actions_adddup2(&actions, err.fileHandleForWriting.fileDescriptor, STDERR_FILENO) == 0 else {
            throw ScriptProcessError.launchFailed
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
        try? input?.fileHandleForReading.close()
        guard launched == 0 else { throw ScriptProcessError.launchFailed }
        let outFD = out.fileHandleForReading.fileDescriptor, errFD = err.fileHandleForReading.fileDescriptor
        _ = fcntl(outFD, F_SETFL, O_NONBLOCK)
        _ = fcntl(errFD, F_SETFL, O_NONBLOCK)

        if let fd = input?.fileHandleForWriting.fileDescriptor {
            guard fcntl(fd, F_SETFL, O_NONBLOCK) == 0, fcntl(fd, F_SETNOSIGPIPE, 1) == 0 else {
                kill(-pid, SIGKILL)
                while waitpid(pid, nil, 0) < 0 && errno == EINTR {}
                throw ScriptProcessError.launchFailed
            }
        }
        return ChildProcess(pid: pid, input: input?.fileHandleForWriting,
                            output: out.fileHandleForReading, error: err.fileHandleForReading)
    }

    func close() {
        try? input?.close(); try? output.close(); try? error.close()
    }
}
