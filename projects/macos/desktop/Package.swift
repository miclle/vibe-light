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
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.3"),
    ],
    targets: [
        .target(
            name: "VibeLightCore"
        ),
        .executableTarget(
            name: "VibeLightApp",
            dependencies: [
                "VibeLightCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            resources: [
                .process("Resources/AppIcon.icns"),
                .process("Resources/Assets.xcassets"),
                .process("Resources/icon.svg"),
                .copy("Resources/FirmwareBundle"),
                .copy("Resources/FirmwareTools"),
            ],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
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
