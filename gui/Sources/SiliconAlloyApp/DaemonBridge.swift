import Foundation

struct DaemonBridge {
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    func fetchServiceInfo() async throws -> ServiceInfo {
        let data = try await run(arguments: ["info"])
        let dto = try decoder.decode(ServiceInfoDTO.self, from: data)
        return ServiceInfo(
            version: dto.version,
            runtimeDir: dto.runtimeDir,
            bottleRoot: dto.bottleRoot,
            runtimes: dto.runtimes
        )
    }

    func listBottles() async throws -> [Bottle] {
        let data = try await run(arguments: ["list"])
        let payload = try decoder.decode(BottleListPayload.self, from: data)
        return payload.bottles.map(Bottle.init)
    }

    func listRecipes() async throws -> [RecipeSummary] {
        let data = try await run(arguments: ["recipes", "list"])
        let payload = try decoder.decode(RecipeListPayload.self, from: data)
        return payload.recipes
    }

    func createBottle(name: String, wineVersion: String, wineLabel: String?, winePath: URL?, channel: String?) async throws {
        var args = ["create", name, "--wine-version", wineVersion]
        if let wineLabel {
            args += ["--wine-label", wineLabel]
        }
        if let winePath {
            args += ["--wine-path", winePath.path]
        }
        if let channel {
            args += ["--channel", channel]
        }
        _ = try await run(arguments: args)
    }

    func deleteBottle(id: UUID) async throws {
        _ = try await run(arguments: ["delete", id.uuidString])
    }

    func runExecutable(id: UUID, executable: URL) async throws {
        _ = try await run(arguments: ["run", id.uuidString, executable.path])
    }

    func applyRecipe(recipeId: String, bottleId: UUID) async throws {
        _ = try await run(arguments: ["recipes", "apply", "--bottle", bottleId.uuidString, "--recipe", recipeId])
    }

    private func run(arguments: [String]) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            let env = ProcessInfo.processInfo.environment
            if let custom = env["SILICON_ALLOY_CLI"], !custom.isEmpty {
                process.executableURL = URL(fileURLWithPath: custom)
                process.arguments = arguments
            } else {
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["silicon-alloy"] + arguments
            }
            let output = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = output
            process.standardError = errorPipe
            try process.run()
            process.waitUntilExit()
            let status = process.terminationStatus
            let data = output.fileHandleForReading.readDataToEndOfFile()
            if status == 0 {
                return data
            }
            let stderr = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: stderr, encoding: .utf8) ?? "unknown error"
            throw BridgeError.processFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }.value
    }
}

enum BridgeError: Error, LocalizedError {
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case .processFailed(let message):
            return message
        }
    }
}

private struct BottleListPayload: Codable {
    let bottles: [BottleRecordDTO]
}

private struct RecipeListPayload: Codable {
    let recipes: [RecipeSummary]
}

