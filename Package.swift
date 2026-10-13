// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "YugiTokenBar",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6"),
    ],
    targets: [
        .executableTarget(
            name: "YugiTokenBar",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/YugiTokenBar",
            exclude: ["Usage/NOTICE.md"],
            // .app 은 Contents/Frameworks, swift run 은 실행 파일 옆의 Sparkle.framework 를 찾는다
            linkerSettings: [.unsafeFlags([
                "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
                "-Xlinker", "-rpath", "-Xlinker", "@loader_path",
            ])]
        ),
        .testTarget(
            name: "YugiTokenBarTests",
            dependencies: ["YugiTokenBar"],
            path: "Tests/YugiTokenBarTests"
        ),
    ]
)
