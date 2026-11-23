// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "FocusFlow",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"),
    ],
    targets: [
        .executableTarget(
            name: "FocusFlow",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/FocusFlow",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("Carbon"),
                // FoundationModels only exists on macOS 26+, so it must be weak-linked
                // for the app to launch on older systems.
                .unsafeFlags(["-Xlinker", "-weak_framework", "-Xlinker", "FoundationModels"]),
            ]
        ),
        .testTarget(
            name: "FocusFlowTests",
            dependencies: ["FocusFlow"],
            path: "Tests/FocusFlowTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // MCP server for Claude; build-app.sh puts it next to the app's binary.
        .executableTarget(
            name: "focusflow-mcp",
            path: "Sources/FocusFlowMCP",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
