import Foundation

enum DaemonClientError: Error, LocalizedError {
    case executableNotFound
    case commandFailed(status: Int32, stderr: String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            return "could not locate alloyctl"
        case .commandFailed(let status, let stderr):
            return "daemon command failed (\(status)): \(stderr)"
        case .invalidResponse:
            return "daemon returned data we could not parse"
        }
    }
}

final class DaemonClient {
    private let executableURL: URL
    private let socketPath: String?

    init(env: [String: String] = ProcessInfo.processInfo.environment) throws {
        if let explicit = env["SILICON_ALLOY_CLI"], !explicit.isEmpty {
            executableURL = URL(fileURLWithPath: explicit)
        } else if let discovered = DaemonClient.searchPATH(env: env) {
            executableURL = discovered
        } else {
            throw DaemonClientError.executableNotFound
        }
        socketPath = env["SILICON_ALLOY_SOCKET"]
    }

    func listBottles() throws -> [Bottle] {
        let data = try runCommand(["list"])
        let decoded = try JSONDecoder().decode([Bottle].self, from: data)
        return decoded
    }

    func createBottle(named name: String) throws -> Bottle {
        let data = try runCommand(["create", name])
        let decoded = try JSONDecoder().decode(Bottle.self, from: data)
        return decoded
    }

    func destroyBottle(named name: String) throws {
        _ = try runCommand(["destroy", name])
    }

    func runExecutable(in name: String, executable: String, args: [String]) throws -> Int32 {
        var command = ["run", name, executable]
        command.append(contentsOf: args)
        let data = try runCommand(command)
        guard
            let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let exitCode = payload["exit_code"] as? Int
        else {
            throw DaemonClientError.invalidResponse
        }
        return Int32(exitCode)
    }

    func ping() throws {
        _ = try runCommand(["ping"])
    }

    private func runCommand(_ args: [String]) throws -> Data {
        let process = Process()
        process.executableURL = executableURL
        var commandArgs = args
        if let socketPath {
            commandArgs.insert(contentsOf: ["--socket", socketPath], at: 0)
        }
        process.arguments = commandArgs

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let status = process.terminationStatus
        if status != 0 {
            let message = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw DaemonClientError.commandFailed(status: status, stderr: message.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return stdout.fileHandleForReading.readDataToEndOfFile()
    }

    private static func searchPATH(env: [String: String]) -> URL? {
        guard let path = env["PATH"] else { return nil }
        for entry in path.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(entry)).appendingPathComponent("alloyctl")
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        let devCandidate = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("core/target/debug/alloy-cli", isDirectory: false)
        if FileManager.default.isExecutableFile(atPath: devCandidate.path) {
            return devCandidate
        }
        return nil
    }
}

