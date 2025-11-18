import Foundation

struct DaemonBridge {
    private let socketPath: String
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    init() {
        socketPath = DaemonBridge.resolveSocketPath()
    }

    func fetchServiceInfo() async throws -> ServiceInfo {
        let dto: ServiceInfoDTO = try await rpc("service.info", params: EmptyParams())
        return ServiceInfo(
            version: dto.version,
            runtimeDir: dto.runtimeDir,
            bottleRoot: dto.bottleRoot,
            runtimes: dto.runtimes
        )
    }

    func listBottles() async throws -> [Bottle] {
        let payload: BottleListPayload = try await rpc("bottle.list", params: EmptyParams())
        return payload.bottles.map(Bottle.init)
    }

    func listRecipes() async throws -> [RecipeSummary] {
        let payload: RecipeListPayload = try await rpc("recipe.list", params: EmptyParams())
        return payload.recipes
    }

    func createBottle(name: String, wineVersion: String, wineLabel: String?, winePath: URL?, channel: String?) async throws {
        let params = BottleCreateRequest(
            name: name,
            wineVersion: wineVersion,
            wineLabel: wineLabel,
            winePath: winePath?.path,
            channel: channel
        )
        _ = try await rpc("bottle.create", params: params) as BottlePayload
    }

    func deleteBottle(id: UUID) async throws {
        let params = BottleIdRequest(id: id)
        _ = try await rpc("bottle.delete", params: params) as DeletePayload
    }

    func runExecutable(id: UUID, executable: URL) async throws {
        let params = BottleRunRequest(id: id, executable: executable.path, args: [])
        _ = try await rpc("bottle.run", params: params) as RunPayload
    }

    func applyRecipe(recipeId: String, bottleId: UUID) async throws {
        let params = RecipeApplyRequest(bottleId: bottleId, recipeId: recipeId)
        _ = try await rpc("recipe.apply", params: params) as RecipeApplyPayload
    }

    func createShortcut(bottleId: UUID, name: String, executable: String, destination: URL?) async throws -> URL {
        let params = ShortcutCreateRequest(
            bottleId: bottleId,
            name: name,
            executable: executable,
            destination: destination?.path
        )
        let payload: ShortcutPayload = try await rpc("shortcut.create", params: params)
        return payload.shortcut
    }

    private func rpc<Params: Encodable, Result: Decodable>(_ method: String, params: Params) async throws -> Result {
        let request = RpcRequest(params: params, method: method)
        let requestData = try encoder.encode(request)
        let responseData = try await Task.detached(priority: .userInitiated) {
            try UnixDomainSocket.request(path: socketPath, payload: requestData)
        }.value
        let envelope = try decoder.decode(RpcEnvelope<Result>.self, from: responseData)
        if let error = envelope.error {
            throw BridgeError.rpcFailed(code: error.code, message: error.message)
        }
        guard let result = envelope.result else {
            throw BridgeError.missingResult
        }
        return result
    }

    private static func resolveSocketPath() -> String {
        if let override = ProcessInfo.processInfo.environment["SILICON_ALLOY_SOCKET"], !override.isEmpty {
            return override
        }
        let fileManager = FileManager.default
        let supportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let socketURL = supportDir?
            .appendingPathComponent("com.SiliconAlloy.SiliconAlloy", isDirectory: true)
            .appendingPathComponent("daemon.sock", isDirectory: false)
        return socketURL?.path ?? "/tmp/silicon-alloy-daemon.sock"
    }
}

enum BridgeError: Error, LocalizedError {
    case rpcFailed(code: Int, message: String)
    case missingResult

    var errorDescription: String? {
        switch self {
        case .rpcFailed(_, let message):
            return message
        case .missingResult:
            return "daemon returned an unexpected response"
        }
    }
}

private struct EmptyParams: Encodable {}

private struct RpcRequest<Params: Encodable>: Encodable {
    let id: UUID
    let method: String
    let params: Params

    init(params: Params, method: String) {
        id = UUID()
        self.method = method
        self.params = params
    }
}

private struct RpcEnvelope<Result: Decodable>: Decodable {
    let id: UUID?
    let result: Result?
    let error: RpcErrorPayload?
}

private struct RpcErrorPayload: Decodable {
    let code: Int
    let message: String
}

private struct BottleListPayload: Codable {
    let bottles: [BottleRecordDTO]
}

private struct RecipeListPayload: Codable {
    let recipes: [RecipeSummary]
}

private struct BottlePayload: Codable {
    let bottle: BottleRecordDTO
}

private struct DeletePayload: Codable {
    let deleted: UUID
}

private struct RunPayload: Codable {
    let exitStatus: Int?
    let success: Bool
}

private struct RecipeApplyPayload: Codable {
    let applied: String
}

private struct BottleCreateRequest: Encodable {
    let name: String
    let wineVersion: String
    let wineLabel: String?
    let winePath: String?
    let channel: String?
}

private struct BottleIdRequest: Encodable {
    let id: UUID
}

private struct BottleRunRequest: Encodable {
    let id: UUID
    let executable: String
    let args: [String]
}

private struct RecipeApplyRequest: Encodable {
    let bottleId: UUID
    let recipeId: String
}

private struct ShortcutCreateRequest: Encodable {
    let bottleId: UUID
    let name: String
    let executable: String
    let destination: String?
}

private struct ShortcutPayload: Decodable {
    let shortcut: URL
}

