import Foundation

/// Installed resources take precedence over the source tree used by development runs.
enum PlatformPaths {
    static func installedResource(_ relativePath: String) -> URL? {
        let candidates: [URL]
        #if os(Linux)
        let override = ProcessInfo.processInfo.environment["YTB_RESOURCES"] ?? ""
        let executable = URL(fileURLWithPath: Bundle.main.executablePath ?? CommandLine.arguments[0])
        candidates = (override.isEmpty ? [] : [URL(fileURLWithPath: override, isDirectory: true)])
            + [executable.deletingLastPathComponent().appendingPathComponent("../share/yugitokenbar").standardizedFileURL]
        #else
        candidates = Bundle.main.resourceURL.map { [$0] } ?? []
        #endif
        return candidates.map { $0.appendingPathComponent(relativePath) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func repoResource(_ relativePath: String) -> URL {
        AppInfo.repoRoot.appendingPathComponent("Resources").appendingPathComponent(relativePath)
    }

    static func resource(_ relativePath: String) -> URL {
        installedResource(relativePath) ?? repoResource(relativePath)
    }
}
