// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacMax",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "MacMaxCore"),
        .executableTarget(name: "MacMax", dependencies: ["MacMaxCore"]),
        .executableTarget(name: "MacMaxProbe", dependencies: ["MacMaxCore"]),
        .executableTarget(name: "MacMaxTests", dependencies: ["MacMaxCore"]),
    ],
    swiftLanguageModes: [.v5]
)
