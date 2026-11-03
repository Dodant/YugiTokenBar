import Foundation
import Testing
@testable import YugiTokenBar

/// Runs only with YTB_BENCH_CLAUDE_ROOT=<folder of Claude jsonl logs>. Read-only. Prints seconds so before/after can be compared.
@Suite struct UsageBenchTests {
    static let root = ProcessInfo.processInfo.environment["YTB_BENCH_CLAUDE_ROOT"].map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }

    @Test(.enabled(if: root != nil)) func coldParseAllFiles() {
        let root = Self.root!
        let t0 = Date()
        let entries = LocalUsageReader.claudeEntries(modifiedSince: .distantPast, roots: [root])
        let files = LocalUsageReader.jsonlFiles(in: root, modifiedSince: .distantPast).count
        print("bench cold parse: \(files) files, \(entries.count) entries, \(String(format: "%.2f", Date().timeIntervalSince(t0))) s")
        #expect(!entries.isEmpty)
    }

    @Test(.enabled(if: root != nil)) func tailFromZeroAllFiles() {
        let root = Self.root!
        let t0 = Date()
        var count = 0
        for file in LocalUsageReader.jsonlFiles(in: root, modifiedSince: .distantPast) {
            var tail = TodayUsageReader.ClaudeTail()
            TodayUsageReader.readTail(file, into: &tail)
            count += tail.entries.count
        }
        print("bench tail from zero: \(count) entries, \(String(format: "%.2f", Date().timeIntervalSince(t0))) s")
        #expect(count > 0)
    }
}
