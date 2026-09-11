// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VictorEffects",
    platforms: [.macOS(.v13)],
    targets: [
        // One executable target, no library split: the tests `@testable import`
        // the executable, which keeps every type internal (the alternative is
        // marking a 9k-line animator `public` for no runtime benefit).
        .executableTarget(
            name: "VictorEffects",
            resources: [.copy("Resources")]
        ),
        .testTarget(
            name: "VictorEffectsTests",
            dependencies: ["VictorEffects"],
            resources: [.copy("Resources")]
        ),
    ]
)
