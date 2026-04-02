import Foundation

public final class SessionGuard {

    public struct ClaudeSession {
        public let pid: Int32
        public let command: String
    }

    public init() {}

    public var hasRunningSessions: Bool {
        runningSessionCount > 0
    }

    public var runningSessionCount: Int {
        findClaudeSessions().count
    }

    public func findClaudeSessions() -> [ClaudeSession] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-fl", "claude"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        return output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 1)
            guard parts.count == 2,
                  let pid = Int32(parts[0]) else { return nil }
            let command = String(parts[1])
            // Filter out ourselves and grep processes
            if command.contains("ClaudeProfileManager") { return nil }
            if command.contains("pgrep") { return nil }
            return ClaudeSession(pid: pid, command: command)
        }
    }
}
