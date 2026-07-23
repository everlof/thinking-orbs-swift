// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ThinkingOrbs",
    platforms: [.iOS(.v15), .macOS(.v13)],
    products: [
        .library(name: "ThinkingOrbs", targets: ["ThinkingOrbs"]),
        .executable(name: "ThinkingOrbsDemo", targets: ["ThinkingOrbsDemo"])
    ],
    targets: [
        .target(name: "ThinkingOrbs"),
        .executableTarget(name: "ThinkingOrbsDemo", dependencies: ["ThinkingOrbs"])
    ]
)
