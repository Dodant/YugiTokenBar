import Foundation
import Testing
@testable import YugiTokenBar

@Suite struct UsageTests {
    @Test func claudeFixtureCountsAllFourBucketsOnce() throws {
        let root = tempDir()
        let project = root.appendingPathComponent("proj")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let ts = ISO8601DateFormatter().string(from: Date())
        let line = #"{"type":"assistant","timestamp":"\#(ts)","requestId":"req1","message":{"id":"msg1","model":"claude-opus-5-5","usage":{"input_tokens":100,"output_tokens":20,"cache_creation_input_tokens":3,"cache_read_input_tokens":4000}}}"#
        // 같은 메시지가 두 번 기록돼도 한 번만 센다
        try (line + "\n" + line + "\n").write(to: project.appendingPathComponent("s.jsonl"), atomically: true, encoding: .utf8)

        let entries = LocalUsageReader.claudeEntries(modifiedSince: Date().addingTimeInterval(-3600), roots: [root])
        let today = LocalUsageReader.localDayFormatter().string(from: Date())
        #expect(TodayUsage.total(entries, day: today) == 4123)
        #expect(TodayUsage.total(entries, day: "1999-01-01") == 0)
    }
}
