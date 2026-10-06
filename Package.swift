// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "lidder",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .target(
            name: "LidderCore",
            resources: [
                .copy("Resources/index.html")
            ]
        ),
        .executableTarget(
            name: "lidder",
            dependencies: ["LidderCore"]
        ),
        .testTarget(
            name: "LidderCoreTests",
            dependencies: ["LidderCore"]
        ),
    ]
)
