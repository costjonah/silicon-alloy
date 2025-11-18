// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SiliconAlloyApp",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "SiliconAlloyApp", targets: ["SiliconAlloyApp"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "SiliconAlloyApp",
            path: "Sources",
            resources: [
                .copy("Assets/AccentColor.colorset"),
                .copy("Assets/AppIcon.appiconset")
            ]
        )
    ]
)

