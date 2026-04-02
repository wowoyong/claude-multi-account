// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeProfileManager",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ClaudeProfileManagerCore", targets: ["ClaudeProfileManagerCore"]),
    ],
    targets: [
        .target(
            name: "ClaudeProfileManagerCore",
            path: "Sources",
            exclude: ["App", "MenuBar", "Dashboard", "Onboarding", "Resources"]
        ),
        .testTarget(
            name: "ClaudeProfileManagerTests",
            dependencies: ["ClaudeProfileManagerCore"],
            path: "Tests"
        ),
    ]
)
