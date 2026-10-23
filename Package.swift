// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "input-smarter",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "input-smarter",
            path: "Sources/input-smarter",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "input-smarterTests",
            dependencies: ["input-smarter"],
            path: "Tests/input-smarterTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
