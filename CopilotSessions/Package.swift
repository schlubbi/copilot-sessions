// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CopilotSessions",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "CopilotSessionsLib",
            path: "Sources/Lib"
        ),
        .executableTarget(
            name: "CopilotSessions",
            dependencies: ["CopilotSessionsLib"],
            path: "Sources/App"
        ),
        .testTarget(
            name: "CopilotSessionsTests",
            dependencies: ["CopilotSessionsLib"],
            path: "Tests"
        ),
    ]
)
