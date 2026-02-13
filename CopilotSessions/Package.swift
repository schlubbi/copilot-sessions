// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CopilotSessions",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "CopilotSessions",
            path: "Sources"
        ),
    ]
)
