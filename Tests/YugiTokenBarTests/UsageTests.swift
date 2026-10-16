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
        #expect(TodayUsageReader.bucket(entries, day: today).total == 4123)
        #expect(TodayUsageReader.bucket(entries, day: "1999-01-01").total == 0)
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

    /// 백오프는 실앱에서 UserDefaults 에 둬, 다시 켠 앱(새 리더)도 그동안 부르지 않는다
    @Test func cursorAPIBackoffSurvivesRestart() async {
        actor Calls { var n = 0; func bump() { n += 1 } }
        let calls = Calls(), suite = UUID().uuidString
        func reader() -> TodayUsageReader {
            TodayUsageReader(claudeRoots: [tempDir()], liveCursor: { _ in
                await calls.bump()
                return .init(entries: [], highWaterByPath: [:], didReset: false, isAuthoritative: false)
            }, backoffStore: UserDefaults(suiteName: suite))
        }
        let t0 = Date(), since = t0.addingTimeInterval(-3600)
        _ = await reader().cursorEntries(modifiedSince: since, now: t0)
        _ = await reader().cursorEntries(modifiedSince: since, now: t0.addingTimeInterval(60))
        #expect(await calls.n == 1)
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
        func total() async -> Int { TodayUsageReader.bucket(await reader.claudeEntries(modifiedSince: since), day: today).total }

        #expect(await total() == 120)
        #expect(await total() == TodayUsageReader.bucket(LocalUsageReader.claudeEntries(modifiedSince: since, roots: [root]), day: today).total)
        try (line("1", 100) + line("3", 5)).write(to: a, atomically: true, encoding: .utf8)
        #expect(await total() == 125)
        try FileManager.default.removeItem(at: b)
        #expect(await total() == 105)
    }

    /// 쓰는 중인 파일은 붙은 줄만 읽어도 통째로 다시 읽은 것과 같다 (덜 쓴 마지막 줄·비용 원장 포함)
    @Test func claudeTailMatchesFullParse() async throws {
        let root = tempDir(), project = root.appendingPathComponent("proj")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let ts = ISO8601DateFormatter().string(from: Date())
        func line(_ id: String, _ output: Int) -> String {
            #"{"type":"assistant","timestamp":"\#(ts)","requestId":"r\#(id)","message":{"id":"m\#(id)","model":"claude-opus-5-5","usage":{"input_tokens":10,"output_tokens":\#(output)}}}"# + "\n"
        }
        let cost = #"{"type":"cost-state","modelUsage":{"claude-opus-5-5":{"costUSD":2.5}}}"# + "\n"
        let file = project.appendingPathComponent("s.jsonl"), fmt = LocalUsageReader.localDayFormatter()
        let since = Date().addingTimeInterval(-3600), today = fmt.string(from: Date())
        func append(_ text: String) throws {
            let h = try FileHandle(forWritingTo: file)
            try h.seekToEnd(); try h.write(contentsOf: Data(text.utf8)); try h.close()
        }
        func full() -> (Int, Double) {
            let b = TodayUsageReader.bucket(LocalUsageReader.parseClaudeFile(file, fmt: fmt), day: today)
            return (b.total, (b.cost * 1e6).rounded())
        }
        func sum(_ entries: [LocalUsageReader.Entry]) -> (Int, Double) {
            let b = TodayUsageReader.bucket(entries, day: today)
            return (b.total, (b.cost * 1e6).rounded())
        }
        try line("1", 5).write(to: file, atomically: true, encoding: .utf8)
        var tail = TodayUsageReader.ClaudeTail()
        let reader = TodayUsageReader(claudeRoots: [root])
        for chunk in [line("1", 50) + String(line("2", 7).dropLast(20)), String(line("2", 7).suffix(20)) + cost, line("3", 1)] {
            TodayUsageReader.readTail(file, into: &tail)
            #expect(sum(tail.costState.map { LocalUsageReader.applyReportedCost(tail.entries, $0) } ?? tail.entries) == full())
            #expect(sum(await reader.claudeEntries(modifiedSince: since)) == full())
            try append(chunk)
        }
        TodayUsageReader.readTail(file, into: &tail)
        #expect(tail.offset == (try Data(contentsOf: file)).count)
        #expect(sum(LocalUsageReader.applyReportedCost(tail.entries, tail.costState!)) == full())
        #expect(sum(await reader.claudeEntries(modifiedSince: since)) == full())
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
                                                  from: "2026-10-05", before: "2026-10-07")
        #expect(totals == ["2026-10-05": 15, "2026-10-06": 7])
    }

    /// 최근에 수정한 세션 파일에 오래된 기록도 있으면, 첫 실행의 14일 범위 밖은 적립하지 않는다
    @Test func firstRunReadExcludesOldEntriesInRecentFile() async throws {
        let root = tempDir(), project = root.appendingPathComponent("proj")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let cal = Calendar.current, iso = ISO8601DateFormatter()
        let now = try #require(cal.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 12)))
        func line(_ day: Int, _ tokens: Int) throws -> String {
            let date = try #require(cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: 12)))
            let ts = iso.string(from: date)
            return #"{"type":"assistant","timestamp":"\#(ts)","requestId":"r\#(day)","message":{"id":"m\#(day)","model":"claude-opus-5-5","usage":{"input_tokens":\#(tokens),"output_tokens":0}}}"# + "\n"
        }
        let log = project.appendingPathComponent("s.jsonl")
        try (line(1, 100) + line(2, 200) + line(15, 300)).write(to: log, atomically: true, encoding: .utf8)
        let cache = LocalUsageCache(claudeRoots: [root], codexRoots: [], geminiRoots: [], grokRoots: [], piRoots: [], ompRoots: [],
                                    fileURL: tempDir().appendingPathComponent("cache.json"))
        let reader = TodayUsageReader(claudeRoots: [root], cache: cache, historyFile: nil, liveCursor: { _ in
            .init(entries: [], highWaterByPath: [:], didReset: false, isAuthoritative: true)
        })
        let usage = await reader.read(since: Game.firstRunSince(now: now), now: now)
        #expect(usage.earlier["2026-10-01"] == nil)
        #expect(usage.earlier["2026-10-02"]?[Provider.claude.rawValue] == 200)
        #expect(usage.earlier["2026-10-15"]?[Provider.claude.rawValue] == 300)
    }

    /// 사용량 화면 합계: 고른 날짜 범위(양 끝 포함)의 모든 provider 를 더한다
    @MainActor @Test func dailyUsageTotalCoversInclusiveRange() {
        func b(_ input: Int) -> TokenSum { var b = TokenSum(); b.input = input; b.cost = Double(input) / 100; return b }
        let days: UsageByDay = ["2026-09-30": ["claude_code": b(1)], "2026-10-01": ["claude_code": b(10), "codex": b(20)],
                                "2026-10-05": ["codex": b(300)], "2026-10-06": ["claude_code": b(4000)]]
        let cal = Calendar.current
        let date = { (d: Int) in cal.date(from: DateComponents(year: 2026, month: 10, day: d, hour: 12))! }
        let t = TodayUsageReader.total(days, from: date(1), through: date(5))
        #expect(t.tokens == 330)
        #expect(abs(t.cost - 3.3) < 1e-9)
        #expect(TodayUsageReader.total(days, from: date(6), through: date(6)).tokens == 4000)
        let chart = UsageDetailView.days(days, now: date(6), count: 6)  // 10/1 ~ 10/6, 날마다 모든 provider 합
        #expect(chart.map(\.tokens) == [30, 0, 0, 0, 300, 4000] && chart[0].byAgent == ["claude_code": 10, "codex": 20])
        #expect(abs(chart[0].cost - 0.3) < 1e-9)
        // 쓴 날(오늘은 늘 셈)이 count 개가 되게 과거로 넓히고, 모자라면 처음 쓴 날부터
        let wide = UsageDetailView.days(days, now: date(6), count: 8)  // 9/29 ~ 10/6
        #expect(UsageDetailView.activeDays(wide, count: 3).map(\.tokens) == [30, 0, 0, 0, 300, 4000])
        #expect(UsageDetailView.activeDays(wide, count: 9).map(\.tokens) == [1, 30, 0, 0, 0, 300, 4000])
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

        let first = await TodayUsageReader(claudeRoots: [root], historyFile: file, liveCursor: nil, otherLogs: { _ in [] }).pastDays()
        #expect(first[day]?["claude_code"]?.total == 75)
        try FileManager.default.removeItem(at: log)
        let second = await TodayUsageReader(claudeRoots: [root], historyFile: file, liveCursor: nil, otherLogs: { _ in [] }).pastDays()
        #expect(second[day]?["claude_code"]?.total == 75)
        #expect(second.count == TodayUsageReader.historyDays)
    }

    /// 개발 실행(테스트 포함)은 지난 날짜 파일을 실앱의 캐시 폴더가 아니라 세이브 폴더에 둔다
    @Test func devHistoryFileStaysInStateDir() {
        let file = TodayUsageReader.defaultHistoryFile
        #expect(file.deletingLastPathComponent() == StateStore.standard().url.deletingLastPathComponent())
        #expect(!file.path.contains("/Library/Caches/"))
    }

    /// 사용량 화면 에이전트 순서: 오늘 많이 쓴 순, Claude·Codex 는 안 써도 보이고 나머지는 기간 안에 쓴 것만
    @MainActor @Test func agentsRankByTodayUsage() {
        func t(_ n: Int) -> TokenSum { var t = TokenSum(); t.input = n; return t }
        let usage: UsageByDay = ["2026-10-11": ["gemini": t(5)], "2026-10-12": ["codex": t(30), "claude_code": t(10)]]
        let order = UsageDetailView.ranked(usage, today: ["codex": t(30), "claude_code": t(10)]).map(\.id)
        #expect(order == [.codex, .claude, .gemini])
    }
}
