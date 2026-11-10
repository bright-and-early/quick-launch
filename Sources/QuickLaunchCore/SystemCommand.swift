import Foundation
import Darwin

public enum SystemCommand {
    /// File-backed output avoids pipe deadlocks for large launchd inventories.
    public static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval? = 10) -> CommandResult {
        let manager = FileManager.default
        let directory = manager.temporaryDirectory.appendingPathComponent("quick-launch-command-" + UUID().uuidString)
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            defer { try? manager.removeItem(at: directory) }
            let stdout = directory.appendingPathComponent("stdout"), stderr = directory.appendingPathComponent("stderr")
            for file in [stdout, stderr] { manager.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600]) }
            let out = try FileHandle(forWritingTo: stdout), err = try FileHandle(forWritingTo: stderr)
            defer { try? out.close(); try? err.close() }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = out; process.standardError = err
            let ended = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in ended.signal() }
            try process.run()
            if let timeout = timeout {
                if ended.wait(timeout: .now() + timeout) == .timedOut {
                    process.terminate()
                    if ended.wait(timeout: .now() + 2) == .timedOut { kill(process.processIdentifier, SIGKILL); ended.wait() }
                    return CommandResult(-1, "", "The command timed out and was stopped.")
                }
            } else {
                // Authorization launches a separate privileged process; wait for its
                // bounded batch rather than killing only the authorization wrapper.
                ended.wait()
            }
            return CommandResult(process.terminationStatus, String(decoding: try Data(contentsOf: stdout), as: UTF8.self), String(decoding: try Data(contentsOf: stderr), as: UTF8.self))
        } catch { return CommandResult(-1, "", error.localizedDescription) }
    }
    public static func launchctl(_ arguments: [String]) -> CommandResult { run("/bin/launchctl", arguments) }
}
