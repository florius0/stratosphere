import Darwin
import Foundation

@MainActor final class OwnedProcess {
    private var livePID: pid_t?
    private(set) var processIdentifier: pid_t = 0
    private(set) var processGroup: pid_t = 0
    private(set) var status: Int32?

    func launch(executable: URL, arguments: [String], outputDescriptor: Int32? = nil) throws {
        guard livePID == nil, processIdentifier == 0 else { throw ProbeFailure("Owned process has already been launched") }
        let strings = [executable.path] + arguments
        guard strings.allSatisfy({ !$0.contains("\0") }) else { throw ProbeFailure("Process argument contains a NUL byte") }
        var argv = strings.map { strdup($0) } + [nil]
        var environment = ProcessInfo.processInfo.environment.sorted { $0.key < $1.key }.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            for value in argv { free(value) }
            for value in environment { free(value) }
        }
        var attributes: posix_spawnattr_t?
        try check(posix_spawnattr_init(&attributes), "initialize spawn attributes")
        defer { posix_spawnattr_destroy(&attributes) }
        var signals = sigset_t()
        sigemptyset(&signals)
        try check(posix_spawnattr_setsigmask(&attributes, &signals), "set child signal mask")
        // Omitting POSIX_SPAWN_SETPGROUP keeps every child in the probe's group,
        // so the independent wrapper can remove it after a probe crash/timeout.
        try check(posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSIGMASK)), "set spawn flags")
        var actions: posix_spawn_file_actions_t?
        try check(posix_spawn_file_actions_init(&actions), "initialize spawn file actions")
        defer { posix_spawn_file_actions_destroy(&actions) }
        if let descriptor = outputDescriptor {
            try check(posix_spawn_file_actions_adddup2(&actions, descriptor, STDOUT_FILENO), "redirect stdout")
            try check(posix_spawn_file_actions_adddup2(&actions, descriptor, STDERR_FILENO), "redirect stderr")
            if descriptor != STDOUT_FILENO, descriptor != STDERR_FILENO {
                try check(posix_spawn_file_actions_addclose(&actions, descriptor), "close inherited output descriptor")
            }
        }
        let group = getpgrp()
        var pid: pid_t = 0
        let error = posix_spawn(&pid, executable.path, &actions, &attributes, &argv, &environment)
        try check(error, "launch \(executable.lastPathComponent)")
        livePID = pid; processIdentifier = pid; processGroup = getpgid(pid)
        guard processGroup == group else {
            try stop()
            throw ProbeFailure("Owned child did not inherit the probe's process group")
        }
    }
    func isRunning() throws -> Bool {
        guard let pid = livePID else { return false }
        var result: Int32 = 0
        let observed = waitpid(pid, &result, WNOHANG)
        if observed == 0 { return true }
        if observed == pid { status = result; livePID = nil; return false }
        if errno == EINTR { return true }
        let error = errno
        if error == ECHILD { livePID = nil }
        throw ProbeFailure("Cannot observe owned child: \(String(cString: strerror(error)))", kind: .assertion)
    }
    func stop(termGrace: Double = 3, killGrace: Double = 3) throws {
        guard try isRunning(), let pid = livePID else { return }
        if kill(pid, SIGTERM) != 0, errno != ESRCH { throw ProbeFailure("Cannot terminate owned child", kind: .cleanup) }
        if try waitForExit(seconds: termGrace) { return }
        if kill(pid, SIGKILL) != 0, errno != ESRCH { throw ProbeFailure("Cannot kill owned child", kind: .cleanup) }
        guard try waitForExit(seconds: killGrace) else { throw ProbeFailure("Owned child did not exit after SIGKILL", kind: .cleanup) }
    }
    func waitForExit(seconds: Double) throws -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        repeat {
            if try !isRunning() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        } while Date() < deadline
        return try !isRunning()
    }
    var terminationStatus: Int32? {
        guard let status else { return nil }
        return status & 0x7f == 0 ? (status >> 8) & 0xff : status & 0x7f
    }
    private func check(_ code: Int32, _ action: String) throws {
        guard code == 0 else { throw ProbeFailure("Cannot \(action): \(String(cString: strerror(code)))") }
    }
}
