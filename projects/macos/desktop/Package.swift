// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "VibeLight",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "VibeLightCore",
            targets: ["VibeLightCore"]
        ),
        .executable(
            name: "VibeLightApp",
            targets: ["VibeLightApp"]
        ),
        .executable(
            name: "vibe-light-hook",
            targets: ["VibeLightHook"]
        ),
    ],
    targets: [
        .target(
            name: "VibeLightCore"
        ),
        .executableTarget(
            name: "VibeLightApp",
            dependencies: ["VibeLightCore"]
        ),
        .executableTarget(
            name: "VibeLightHook",
            dependencies: ["VibeLightCore"]
        ),
        .testTarget(
            name: "VibeLightCoreTests",
            dependencies: ["VibeLightCore"]
        ),
    ]
)
