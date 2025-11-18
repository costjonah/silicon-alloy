// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SiliconAlloyApp",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "SiliconAlloyApp",
            targets: ["SiliconAlloyApp"]
        )
    ],
    targets: [
        .executableTarget(
            name: "SiliconAlloyApp",
            dependencies: [],
            path: "Sources"
        )
    ]
)

