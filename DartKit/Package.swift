// swift-tools-version: 6.0
import PackageDescription

/// Warnings (not errors) for data races while the package stays in Swift 5 language mode.
let strict: [SwiftSetting] = [.enableExperimentalFeature("StrictConcurrency")]

let package = Package(
    name: "DartKit",
    defaultLocalization: "fr",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DartCore", targets: ["DartCore"]),
        .library(name: "DartGames", targets: ["DartGames"]),
        .library(name: "DartVision", targets: ["DartVision"]),
        .library(name: "DartAudio", targets: ["DartAudio"]),
        .library(name: "DartUI", targets: ["DartUI"]),
        .executable(name: "SnapshotTool", targets: ["SnapshotTool"]),
    ],
    targets: [
        .target(name: "DartCore", swiftSettings: strict),
        .target(name: "DartGames", dependencies: ["DartCore"], swiftSettings: strict),
        .target(name: "DartVision", dependencies: ["DartCore"], swiftSettings: strict),
        .target(name: "DartAudio", dependencies: ["DartCore"], swiftSettings: strict),
        .target(
            name: "DartUI",
            dependencies: ["DartCore", "DartGames", "DartVision", "DartAudio"],
            resources: [.process("Resources")],
            swiftSettings: strict
        ),
        .executableTarget(name: "SnapshotTool", dependencies: ["DartUI", "DartCore"], swiftSettings: strict),

        // Test-only helpers (GAMES.md §2.11 vector DSL). Not a product: never linked into the app.
        .target(name: "DartTestSupport", dependencies: ["DartCore"], swiftSettings: strict),

        .testTarget(name: "DartCoreTests", dependencies: ["DartCore", "DartTestSupport"]),
        .testTarget(name: "DartGamesTests", dependencies: ["DartGames", "DartCore", "DartTestSupport"]),
        .testTarget(name: "DartVisionTests", dependencies: ["DartVision", "DartCore"]),
        .testTarget(name: "DartAudioTests", dependencies: ["DartAudio", "DartCore"]),
        .testTarget(
            name: "DartUITests",
            dependencies: ["DartUI", "DartGames", "DartVision", "DartAudio", "DartCore", "DartTestSupport"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
