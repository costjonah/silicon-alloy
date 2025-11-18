import Foundation

struct Bottle: Identifiable, Decodable {
    var id: String { name }
    let name: String
    private let pathString: String?
    let runtime: RuntimeMetadata

    var pathURL: URL? {
        guard let pathString else { return nil }
        return URL(fileURLWithPath: pathString)
    }

    enum CodingKeys: String, CodingKey {
        case name
        case pathString = "path"
        case runtime
    }
}

struct RuntimeMetadata: Decodable {
    let version: String
    let arch: String
    let builtAt: String?
    let sdkPath: String?
    let sdkVersion: String?
    let minMacos: String?

    enum CodingKeys: String, CodingKey {
        case version
        case arch
        case builtAt = "built_at"
        case sdkPath = "sdk_path"
        case sdkVersion = "sdk_version"
        case minMacos = "min_macos"
    }
}

