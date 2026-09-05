// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "nootch",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "nootch", targets: ["Nootch"]),
    ],
    targets: [
        .executableTarget(
            name: "Nootch",
            resources: [.process("Resources")]),
        .testTarget(name: "NootchTests", dependencies: ["Nootch"]),
    ]
)
