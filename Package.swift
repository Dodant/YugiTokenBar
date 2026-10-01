// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "YugiTokenBar",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "YugiTokenBar",
            path: "Sources/YugiTokenBar",
            exclude: ["Usage/NOTICE.md"]
        ),
        .testTarget(
            name: "YugiTokenBarTests",
            dependencies: ["YugiTokenBar"],
            path: "Tests/YugiTokenBarTests"
        ),
    ]
)
