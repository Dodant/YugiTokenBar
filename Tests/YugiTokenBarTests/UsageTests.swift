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

    /// 파일별 캐시: 캐시 없는 경로와 같은 값, 줄이 붙으면 다시 읽고, 지운 파일은 빠진다
    @Test func todayReaderCachesPerFileAndFollowsChanges() async throws {
        let root = tempDir()
        let project = root.appendingPathComponent("proj")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let ts = ISO8601DateFormatter().string(from: Date())
        func line(_ id: String, _ input: Int) -> String {
            #"{"type":"assistant","timestamp":"\#(ts)","requestId":"r\#(id)","message":{"id":"m\#(id)","model":"claude-opus-5-5","usage":{"input_tokens":\#(input),"output_tokens":0}}}"# + "\n"
        }
        let a = project.appendingPathComponent("a.jsonl"), b = project.appendingPathComponent("b.jsonl")
        try line("1", 100).write(to: a, atomically: true, encoding: .utf8)
        try line("2", 20).write(to: b, atomically: true, encoding: .utf8)
        let since = Date().addingTimeInterval(-3600)
        let today = LocalUsageReader.localDayFormatter().string(from: Date())
        let reader = TodayUsageReader(claudeRoots: [root])
        func total() async -> Int { TodayUsage.total(await reader.claudeEntries(modifiedSince: since), day: today) }

        #expect(await total() == 120)
        #expect(await total() == TodayUsage.total(LocalUsageReader.claudeEntries(modifiedSince: since, roots: [root]), day: today))
        try (line("1", 100) + line("3", 5)).write(to: a, atomically: true, encoding: .utf8)
        #expect(await total() == 125)
        try FileManager.default.removeItem(at: b)
        #expect(await total() == 105)
    }

    /// 읽기 시작: 원장 날짜 0시, 오늘보다 뒤면 오늘, 너무 오래면 catchUpDays 전까지
    @Test func catchUpStartFollowsLedgerDay() {
        let cal = Calendar.current
        let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 15))!
        let today = cal.startOfDay(for: now)
        let day = { (n: Int) in cal.date(byAdding: .day, value: n, to: today)! }
        #expect(TodayUsageReader.start(since: nil, now: now) == today)
        #expect(TodayUsageReader.start(since: "2026-10-05", now: now) == day(-2))
        #expect(TodayUsageReader.start(since: "2026-10-09", now: now) == today)
        #expect(TodayUsageReader.start(since: "2025-01-01", now: now) == day(-TodayUsageReader.catchUpDays))
    }

    @Test func totalsByDayLeavesOutToday() {
        func entry(_ day: String, _ input: Int) -> LocalUsageReader.Entry {
            LocalUsageReader.Entry(id: UUID().uuidString, date: Date(), localDay: day, model: "claude-opus-5-5",
                                   input: input, output: 0, cacheWrite: 0, cacheRead: 0)
        }
        let totals = TodayUsageReader.totalsByDay([entry("2026-10-05", 10), entry("2026-10-05", 5), entry("2026-10-06", 7), entry("2026-10-07", 100)],
                                                  before: "2026-10-07")
        #expect(totals == ["2026-10-05": 15, "2026-10-06": 7])
    }
}
