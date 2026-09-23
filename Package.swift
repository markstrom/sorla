// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Sorla",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", .upToNextMinor(from: "0.16.1")),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "3.1.0"),
    ],
    targets: [
        .target(
            name: "SorlaCore",
            dependencies: [
                "FluidAudio",
                "KeyboardShortcuts",
            ],
            path: "Sources/SorlaCore"
        ),
        .executableTarget(
            name: "Sorla",
            dependencies: ["SorlaCore", "KeyboardShortcuts"],
            path: "Sources/Sorla"
        ),
        .testTarget(
            name: "SorlaCoreTests",
            dependencies: ["SorlaCore"],
            path: "Tests/SorlaCoreTests"
        ),
        .testTarget(
            name: "SorlaTests",
            dependencies: ["Sorla"],
            path: "Tests/SorlaTests"
        ),
    ]
)
