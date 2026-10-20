import Foundation

/// Runs command-line tools synchronously. Always call from a background task.
enum Shell {
    struct Result {
        let status: Int32
        let output: String
        let error: String

        var succeeded: Bool { status == 0 }
        var wasCancelledByUser: Bool { error.contains("-128") }
    }

    static func run(_ executable: String, _ arguments: [String] = [], environment: [String: String]? = nil) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        }

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return Result(status: -1, output: "", error: error.localizedDescription)
        }

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return Result(
            status: process.terminationStatus,
            output: String(decoding: outData, as: UTF8.self),
            error: String(decoding: errData, as: UTF8.self)
        )
    }

    /// Runs a shell command with administrator privileges.
    /// macOS shows its own password dialog; the app never sees the password.
    static func runAsAdministrator(_ command: String) -> Result {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escaped)\" with administrator privileges"
        return run("/usr/bin/osascript", ["-e", script])
    }

    static func runAppleScript(_ source: String) -> Result {
        run("/usr/bin/osascript", ["-e", source])
    }
}
