// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentNotch",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "AgentNotch", targets: ["AgentNotch"]),
    ],
    targets: [
        .executableTarget(
            name: "AgentNotch",
            resources: [.process("Resources")]),
        .testTarget(name: "AgentNotchTests", dependencies: ["AgentNotch"]),
    ]
)
