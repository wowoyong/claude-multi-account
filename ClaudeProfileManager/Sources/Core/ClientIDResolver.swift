import Foundation

public final class ClientIDResolver {

    public static let fallbackClientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

    public init() {}

    public func resolve() -> String {
        if let cliPath = findCLIPath(),
           let extracted = extractFromCLI(at: cliPath) {
            if extracted != Self.fallbackClientID {
                print("[ClientIDResolver] Extracted client_id differs from fallback: \(extracted)")
            }
            return extracted
        }
        return Self.fallbackClientID
    }

    public func extractFromCLI(at path: String) -> String? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/grep")
        process.arguments = ["-oE", #"CLIENT_ID:"[0-9a-f-]{36}""#, path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }

        // Extract UUID from CLIENT_ID:"uuid"
        let pattern = #"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let range = Range(match.range, in: output) else { return nil }

        return String(output[range])
    }

    private func findCLIPath() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["claude"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty else { return nil }

        // Resolve symlinks to find the actual cli.js
        // claude binary -> npm global -> @anthropic-ai/claude-code/cli.js
        let resolved = (output as NSString).resolvingSymlinksInPath
        let dir = (resolved as NSString).deletingLastPathComponent
        let npmBase = (dir as NSString).deletingLastPathComponent
        let cliJS = "\(npmBase)/lib/node_modules/@anthropic-ai/claude-code/cli.js"

        if FileManager.default.fileExists(atPath: cliJS) { return cliJS }
        return nil
    }
}
