// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "OnDeviceAIEngine",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "EdgeAIEngine", targets: ["EdgeAIEngine"]),
        .library(name: "EdgeAIIOS", targets: ["EdgeAIIOS"]),
        .executable(name: "edgeai", targets: ["EdgeAIEngineCLI"]),
        .executable(name: "edgeai-hotkey", targets: ["EdgeAIHotkey"])
    ],
    targets: [
        .target(
            name: "EdgeAINativeKernels",
            publicHeadersPath: "include"
        ),
        .target(
            name: "EdgeAIEngine",
            dependencies: ["EdgeAINativeKernels"],
            linkerSettings: [
                .linkedFramework("Metal"),
                .linkedFramework("NaturalLanguage")
            ]
        ),
        .target(
            name: "EdgeAIIOS",
            dependencies: ["EdgeAIEngine"],
            linkerSettings: [
                .linkedFramework("SwiftUI"),
                .linkedFramework("UniformTypeIdentifiers")
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
            dependencies: ["EdgeAIEngine", "EdgeAIIOS"]
        )
    ],
    swiftLanguageModes: [.v5],
    cxxLanguageStandard: .cxx17
)
