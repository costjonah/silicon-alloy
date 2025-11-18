import Foundation

struct Bottle: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var createdAt: Date
    var wineRuntime: WineRuntime
    var environment: [EnvironmentPair]

    var createdAtFormatted: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }
}

struct WineRuntime: Codable, Equatable {
    var label: String
    var wine64Path: URL
    var version: String
    var channel: String?
}

struct EnvironmentPair: Codable, Equatable {
    var key: String
    var value: String
}

struct ServiceInfo: Codable {
    var version: String
    var runtimeDir: URL
    var bottleRoot: URL
    var runtimes: [RuntimeDescriptorInfo]
}

struct RecipeSummary: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var description: String?
}

struct RuntimeDescriptorInfo: Identifiable, Codable, Equatable {
    var channel: String
    var label: String
    var version: String
    var wine64Path: URL
    var notes: String?

    var id: String { "\(channel)-\(version)-\(wine64Path.path)" }
}

extension Bottle {
    init(_ record: BottleRecordDTO) {
        id = record.id
        name = record.name
        createdAt = Date(timeIntervalSince1970: TimeInterval(record.createdAt))
        wineRuntime = WineRuntime(
            label: record.wineRuntime.label,
            wine64Path: record.wineRuntime.wine64Path,
            version: record.wineRuntime.version,
            channel: record.wineRuntime.channel
        )
        environment = record.environment.map { EnvironmentPair(key: $0.0, value: $0.1) }
    }
}

// DTOs used for decoding raw daemon payloads
struct BottleRecordDTO: Codable {
    let id: UUID
    let name: String
    let createdAt: UInt64
    let wineRuntime: WineRuntimeDTO
    let environment: [(String, String)]

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case createdAt = "created_at"
        case wineRuntime = "wine_runtime"
        case environment
    }
}

struct WineRuntimeDTO: Codable {
    let label: String
    let wine64Path: URL
    let version: String
    let channel: String?

    enum CodingKeys: String, CodingKey {
        case label
        case wine64Path = "wine64_path"
        case version
        case channel
    }
}

struct ServiceInfoDTO: Codable {
    let version: String
    let runtimeDir: URL
    let bottleRoot: URL
    let runtimes: [RuntimeDescriptorInfo]

    enum CodingKeys: String, CodingKey {
        case version
        case runtimeDir = "runtime_dir"
        case bottleRoot = "bottle_root"
        case runtimes
    }
}

