// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "OnDeviceAIEngine",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "EdgeAIEngine", targets: ["EdgeAIEngine"]),
        .executable(name: "edgeai", targets: ["EdgeAIEngineCLI"]),
        .executable(name: "edgeai-hotkey", targets: ["EdgeAIHotkey"])
    ],
    targets: [
        .target(
            name: "EdgeAIEngine",
            linkerSettings: [
                .linkedFramework("NaturalLanguage")
            ]
        ),
        .executableTarget(
            name: "EdgeAIEngineCLI",
            dependencies: ["EdgeAIEngine"]
        ),
        .executableTarget(
            name: "EdgeAIHotkey",
            dependencies: ["EdgeAIEngine"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .testTarget(
            name: "EdgeAIEngineTests",
            dependencies: ["EdgeAIEngine"]
        )
    ],
    swiftLanguageModes: [.v5]
)
