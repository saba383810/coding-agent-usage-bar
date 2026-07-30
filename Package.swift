// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CodingAgentUsageBar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "CodingAgentUsageBar",
            path: "Sources/CodingAgentUsageBar"
        )
    ]
)
