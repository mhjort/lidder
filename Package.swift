// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "lidder",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "lidder",
            path: "Sources/lidder",
            resources: [
                .copy("Resources/index.html")
            ]
        )
    ]
)
