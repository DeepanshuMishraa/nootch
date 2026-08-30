// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UsageNotch",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "UsageNotch", targets: ["UsageNotch"]),
    ],
    targets: [
        .executableTarget(
            name: "UsageNotch",
            resources: [.process("Resources")]),
        .testTarget(name: "UsageNotchTests", dependencies: ["UsageNotch"]),
    ]
)
