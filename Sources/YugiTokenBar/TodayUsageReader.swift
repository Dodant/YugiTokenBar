import Foundation

/// 사용량을 읽는 에이전트. rawValue 는 `byProvider`·세이브 원장(`claimedByProvider`)의 키.
enum Provider: String, CaseIterable, Sendable {
    case claude = "claude_code", codex, gemini, grok, pi, omp, cursor
}

/// `TodayUsage.read` 와 같은 결과를 내되, Claude 로그는 파일마다 (수정 시각, 크기)가 그대로면 다시 파싱하지 않는다.
/// 오늘 바뀐 Claude JSONL(수십~수백 MB)을 60초마다 통째로 다시 읽던 비용을 줄인다.
/// `Usage/` 는 PokeTokenBar 복사본이라 고치지 않고, 그 공개 함수(`jsonlFiles`·`parseClaudeFile`·`dedupKeepMax`)로 감싼다.
// ponytail: 쓰는 중인 세션 파일은 매번 통째로 다시 읽는다. 더 줄이려면 파일 끝에 붙은 줄만 읽는 증분 파서가 필요(Usage/ 수정)
actor TodayUsageReader {
    private struct Parsed { let mtime: Date; let size: Int; let entries: [LocalUsageReader.Entry] }
    private var claude: [URL: Parsed] = [:]
    /// 테스트용. nil 이면 `LocalUsageReader.claudeProjectRoots`
    private let claudeRoots: [URL]?

    init(claudeRoots: [URL]? = nil) { self.claudeRoots = claudeRoots }

    /// 꺼져 있던 날을 거슬러 읽는 최대 일 수. Claude Code 가 기본으로 30일 지난 대화 기록을 지우므로 그보다 앞은 읽을 게 없다.
    static let catchUpDays = 30

    /// since: 적립 원장 날짜(`claimedDate`). 오늘보다 앞이면 그날부터 어제까지의 날짜별 합계도 `earlier`로 돌려준다
    /// (앱이 꺼져 있던 날·자정 직전 몫을 `Game.claim`이 적립). 오늘 몫은 `TodayUsage.read`와 같다.
    func read(since: String? = nil, now: Date = Date())
        async -> (date: String, byProvider: [String: Int], cost: [String: Double], earlier: [String: [String: Int]]) {
        let today = LocalUsageReader.localDayFormatter().string(from: now)
        let start = Self.start(since: since, now: now)
        // 아래는 Claude 를 캐시에서 읽는 것만 빼면 TodayUsage.read 와 같다
        let cursor = AppEnv.allowsLiveLimitsFetch
            ? await LocalAdditionalUsageReader.cursorEntriesAsync(modifiedSince: start).entries
            : LocalAdditionalUsageReader.cursorEntries(modifiedSince: start).entries
        var tokens: [String: Int] = [:], cost: [String: Double] = [:], earlier: [String: [String: Int]] = [:]
        for (provider, entries) in [
            (Provider.claude, claudeEntries(modifiedSince: start)),
            (.codex, LocalUsageReader.codexEntries(modifiedSince: start)),
            (.gemini, LocalUsageReader.geminiEntries(modifiedSince: start)),
            (.grok, LocalUsageReader.grokEntries(modifiedSince: start)),
            (.pi, LocalUsageReader.piEntries(modifiedSince: start)),
            (.omp, LocalUsageReader.ompEntries(modifiedSince: start)),
            (.cursor, cursor),
        ] {
            let b = TodayUsage.bucket(entries, day: today)
            tokens[provider.rawValue] = b.total
            cost[provider.rawValue] = b.cost
            for (day, total) in Self.totalsByDay(entries, before: today) { earlier[day, default: [:]][provider.rawValue] = total }
        }
        return (today, tokens, cost, earlier)
    }

    /// 읽기 시작 시각: 원장 날짜의 0시(오늘보다 뒤면 오늘, `catchUpDays`보다 앞이면 그만큼만).
    static func start(since: String?, now: Date) -> Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        guard let since, let day = LocalUsageReader.localDayFormatter().date(from: since) else { return today }
        let oldest = cal.date(byAdding: .day, value: -catchUpDays, to: today) ?? today
        return min(max(cal.startOfDay(for: day), oldest), today)
    }

    /// 오늘보다 앞 날짜별 토큰 합계 (`TodayUsage.bucket`과 같은 계산)
    static func totalsByDay(_ entries: [LocalUsageReader.Entry], before today: String) -> [String: Int] {
        Dictionary(grouping: entries.filter { $0.localDay < today }, by: \.localDay)
            .mapValues { TodayUsage.bucket($0, day: $0[0].localDay).total }
    }

    /// `LocalUsageReader.claudeEntries(modifiedSince:roots:)` 와 같은 결과. 목록에서 빠진 파일은 캐시에서도 지운다.
    func claudeEntries(modifiedSince: Date) -> [LocalUsageReader.Entry] {
        let fmt = LocalUsageReader.localDayFormatter()
        var all: [LocalUsageReader.Entry] = []
        var kept: [URL: Parsed] = [:]
        for root in claudeRoots ?? LocalUsageReader.claudeProjectRoots {
            for file in LocalUsageReader.jsonlFiles(in: root, modifiedSince: modifiedSince) {
                let v = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                let mtime = v?.contentModificationDate ?? .distantPast, size = v?.fileSize ?? -1
                let parsed = claude[file].flatMap { $0.mtime == mtime && $0.size == size ? $0 : nil }
                    ?? Parsed(mtime: mtime, size: size, entries: LocalUsageReader.parseClaudeFile(file, fmt: fmt))
                kept[file] = parsed
                all += parsed.entries
            }
        }
        claude = kept
        return LocalUsageReader.dedupKeepMax(all)
    }
}
