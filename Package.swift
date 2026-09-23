// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Prata",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.16.1"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "3.1.0"),
    ],
    targets: [
        .target(
            name: "PrataCore",
            dependencies: [
                "FluidAudio",
                "KeyboardShortcuts",
            ],
            path: "Sources/PrataCore"
        ),
        .executableTarget(
            name: "Prata",
            dependencies: ["PrataCore"],
            path: "Sources/Prata"
        ),
        .testTarget(
            name: "PrataCoreTests",
            dependencies: ["PrataCore"],
            path: "Tests/PrataCoreTests"
        ),
    ]
)
