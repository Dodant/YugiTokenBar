// swift-tools-version: 6.2
import PackageDescription

// Keep platform-specific packages out of the other platform's dependency graph.
#if os(Linux)
let platformPackages: [Package.Dependency] = [
    .package(url: "https://github.com/apple/swift-crypto.git", exact: "3.15.1"),
    .package(url: "https://git.aparoksha.dev/aparoksha/adwaita-swift", revision: "af5598fbd6f2425841f426ad388d7a7edd6c90e6"),
]
let platformProducts: [Target.Dependency] = [
    .product(name: "Crypto", package: "swift-crypto"),
    .product(name: "Adwaita", package: "adwaita-swift"),
    .product(name: "CAdw", package: "adwaita-swift"),
    "CSQLite",
]
let testProducts = platformProducts
let platformTargets: [Target] = [
    .systemLibrary(name: "CSQLite", path: "Sources/CSQLite", pkgConfig: "sqlite3", providers: [.apt(["libsqlite3-dev"])]),
]
#else
let platformPackages: [Package.Dependency] = [
    .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6"),
]
let platformProducts: [Target.Dependency] = [
    .product(name: "Sparkle", package: "Sparkle"),
]
let testProducts: [Target.Dependency] = []
let platformTargets: [Target] = []
#endif

let package = Package(
    name: "YugiTokenBar",
    platforms: [.macOS(.v26)],
    dependencies: platformPackages,
    targets: [
        .executableTarget(
            name: "YugiTokenBar",
            dependencies: platformProducts,
            path: "Sources/YugiTokenBar",
            exclude: ["Usage/NOTICE.md"],
            // .app 은 Contents/Frameworks, swift run 은 실행 파일 옆의 Sparkle.framework 를 찾는다
            linkerSettings: [.unsafeFlags([
                "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
                "-Xlinker", "-rpath", "-Xlinker", "@loader_path",
            ], .when(platforms: [.macOS]))]
        ),
        .testTarget(
            name: "YugiTokenBarTests",
            dependencies: ["YugiTokenBar"] + testProducts,
            path: "Tests/YugiTokenBarTests"
        ),
    ] + platformTargets
)
