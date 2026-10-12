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

    /// Cursor API 가 실패하면 백오프 동안 다시 부르지 않고 로컬만 읽고, 지나면 다시 부른다
    @Test func cursorAPIBacksOffAfterFailure() async {
        actor Calls { var n = 0; func bump() { n += 1 } }
        let calls = Calls()
        let reader = TodayUsageReader(claudeRoots: [tempDir()], liveCursor: { _ in
            await calls.bump()
            return .init(entries: [], highWaterByPath: [:], didReset: false, isAuthoritative: false)
        })
        let t0 = Date(), since = t0.addingTimeInterval(-3600)
        _ = await reader.cursorEntries(modifiedSince: since, now: t0)
        _ = await reader.cursorEntries(modifiedSince: since, now: t0.addingTimeInterval(60))
        #expect(await calls.n == 1)
        _ = await reader.cursorEntries(modifiedSince: since, now: t0.addingTimeInterval(TodayUsageReader.cursorAPIBackoff + 1))
        #expect(await calls.n == 2)
    }

    /// 대시보드 API 가 성공(권위 있는 결과)하면 백오프 없이 매번 부른다
    @Test func cursorAPIKeepsCallingAfterSuccess() async {
        actor Calls { var n = 0; func bump() { n += 1 } }
        let calls = Calls()
        let reader = TodayUsageReader(claudeRoots: [tempDir()], liveCursor: { _ in
            await calls.bump()
            return .init(entries: [], highWaterByPath: [:], didReset: false, isAuthoritative: true)
        })
        let t0 = Date(), since = t0.addingTimeInterval(-3600)
        _ = await reader.cursorEntries(modifiedSince: since, now: t0)
        _ = await reader.cursorEntries(modifiedSince: since, now: t0.addingTimeInterval(60))
        #expect(await calls.n == 2)
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

    /// 사용량 화면 합계: 고른 날짜 범위(양 끝 포함)의 모든 provider 를 더한다
    @Test func dailyUsageTotalCoversInclusiveRange() {
        func b(_ input: Int) -> TokenSum { var b = TokenSum(); b.input = input; b.cost = Double(input) / 100; return b }
        let days: UsageByDay = ["2026-09-30": ["claude_code": b(1)], "2026-10-01": ["claude_code": b(10), "codex": b(20)],
                                "2026-10-05": ["codex": b(300)], "2026-10-06": ["claude_code": b(4000)]]
        let cal = Calendar.current
        let date = { (d: Int) in cal.date(from: DateComponents(year: 2026, month: 10, day: d, hour: 12))! }
        let t = TodayUsageReader.total(days, from: date(1), through: date(5))
        #expect(t.tokens == 330)
        #expect(abs(t.cost - 3.3) < 1e-9)
        #expect(TodayUsageReader.total(days, from: date(6), through: date(6)).tokens == 4000)
    }

    /// 지난 날짜 합계는 파일에 남아, 로그가 지워진 뒤 새 리더도 다시 읽지 않고 같은 값을 낸다
    @Test func pastDaysPersistAcrossReaders() async throws {
        let root = tempDir(), project = root.appendingPathComponent("proj")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let twoDaysAgo = Date().addingTimeInterval(-2 * 86_400)
        let ts = ISO8601DateFormatter().string(from: twoDaysAgo)
        let line = #"{"type":"assistant","timestamp":"\#(ts)","requestId":"r1","message":{"id":"m1","model":"claude-opus-5-5","usage":{"input_tokens":70,"output_tokens":5}}}"#
        let log = project.appendingPathComponent("s.jsonl")
        try (line + "\n").write(to: log, atomically: true, encoding: .utf8)
        let file = tempDir().appendingPathComponent("days.json")
        let day = LocalUsageReader.localDayFormatter().string(from: twoDaysAgo)

        let first = await TodayUsageReader(claudeRoots: [root], historyFile: file, liveCursor: nil).pastDays()
        #expect(first[day]?["claude_code"]?.total == 75)
        try FileManager.default.removeItem(at: log)
        let second = await TodayUsageReader(claudeRoots: [root], historyFile: file, liveCursor: nil).pastDays()
        #expect(second[day]?["claude_code"]?.total == 75)
        #expect(second.count == TodayUsageReader.historyDays)
    }

    /// 사용량 화면 에이전트 순서: 오늘 많이 쓴 순, Claude·Codex 는 안 써도 보이고 나머지는 기간 안에 쓴 것만
    @MainActor @Test func agentsRankByTodayUsage() {
        func t(_ n: Int) -> TokenSum { var t = TokenSum(); t.input = n; return t }
        let usage: UsageByDay = ["2026-10-11": ["gemini": t(5)], "2026-10-12": ["codex": t(30), "claude_code": t(10)]]
        let order = UsageDetailView.ranked(usage, today: ["codex": t(30), "claude_code": t(10)]).map(\.id)
        #expect(order == [.codex, .claude, .gemini])
    }
}
