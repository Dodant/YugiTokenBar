import Foundation

/// 입력·출력·캐시 토큰과 비용 합계 (사용량 화면, 날짜별 디스크 캐시)
struct TokenSum: Codable, Equatable, Sendable {
    var input = 0, output = 0, cacheWrite = 0, cacheRead = 0
    var cost = 0.0
    var total: Int { input + output + cacheWrite + cacheRead }

    init() {}
    init(_ b: LocalUsageReader.Bucket) {
        input = b.input; output = b.output; cacheWrite = b.cacheWrite; cacheRead = b.cacheRead; cost = b.cost
    }
}

/// 날짜(`localDay`, yyyy-MM-dd) → provider rawValue → 그날 합계. 사용량 화면의 30일 막대·이번 주·이번 달.
typealias UsageByDay = [String: [String: TokenSum]]

/// 사용량을 읽는 에이전트. rawValue 는 `byProvider`·세이브 원장(`claimedByProvider`)의 키.
enum Provider: String, CaseIterable, Sendable {
    case claude = "claude_code", codex, gemini, grok, pi, omp, cursor
}

/// 오늘(로컬 날짜) provider별 누적 토큰과 비용을 읽는다. 토큰 = input + output + cacheWrite + cacheRead (PokeTokenBar 와 동일).
/// Claude 로그는 파일마다 (수정 시각, 크기)가 그대로면 다시 파싱하지 않는다.
/// 오늘 바뀐 Claude JSONL(수십~수백 MB)을 60초마다 통째로 다시 읽던 비용을 줄인다.
/// `Usage/` 는 PokeTokenBar 복사본이라 고치지 않고, 그 공개 함수(`jsonlFiles`·`parseClaudeFile`·`dedupKeepMax`)로 감싼다.
/// Cursor 대시보드 API는 실패하면 30분 백오프(그동안 로컬 `state.vscdb`만 읽는다).
// ponytail: 쓰는 중인 세션 파일은 매번 통째로 다시 읽는다. 더 줄이려면 파일 끝에 붙은 줄만 읽는 증분 파서가 필요(Usage/ 수정)
actor TodayUsageReader {
    private struct Parsed { let mtime: Date; let size: Int; let entries: [LocalUsageReader.Entry] }
    private var claude: [URL: Parsed] = [:]
    /// 테스트용. nil 이면 `LocalUsageReader.claudeProjectRoots`
    private let claudeRoots: [URL]?

    /// 대시보드 API 가 실패하면(토큰 없음·HTTP 오류) 이만큼은 다시 부르지 않고 로컬 `state.vscdb`만 읽는다. 매분 실패하는 네트워크 호출을 막는다.
    static let cursorAPIBackoff: TimeInterval = 30 * 60
    private var cursorAPIRetryAt = Date.distantPast
    /// 대시보드 API 경로. 실앱·`PTB_PARITY=1`(`AppEnv.allowsLiveLimitsFetch`)에서만 있고, 테스트는 가짜를 넣는다.
    private let liveCursor: (@Sendable (Date) async -> LocalAdditionalUsageReader.CursorLoadResult)?

    /// 지난 날짜별 합계 파일. nil 이면 디스크에 두지 않는다
    private let historyFile: URL?
    /// Claude·Cursor 밖 provider 의 로그 읽기. 테스트는 빈 결과를 넣어 이 Mac 의 실제 로그를 읽지 않는다
    private let otherLogs: @Sendable (Date) -> [(Provider, [LocalUsageReader.Entry])]

    init(claudeRoots: [URL]? = nil,
         historyFile: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("YugiTokenBar/usage-days.json"),
         liveCursor: (@Sendable (Date) async -> LocalAdditionalUsageReader.CursorLoadResult)? =
            AppEnv.allowsLiveLimitsFetch ? { @Sendable in await LocalAdditionalUsageReader.cursorEntriesAsync(modifiedSince: $0) } : nil,
         otherLogs: @escaping @Sendable (Date) -> [(Provider, [LocalUsageReader.Entry])] = TodayUsageReader.localOtherLogs) {
        self.claudeRoots = claudeRoots
        self.historyFile = historyFile
        self.liveCursor = liveCursor
        self.otherLogs = otherLogs
    }

    /// Cursor: 대시보드 API 가 있으면 그것, 실패(`isAuthoritative == false`)하면 `cursorAPIBackoff` 동안 로컬만.
    func cursorEntries(modifiedSince start: Date, now: Date) async -> [LocalUsageReader.Entry] {
        guard let liveCursor, now >= cursorAPIRetryAt else {
            return LocalAdditionalUsageReader.cursorEntries(modifiedSince: start).entries
        }
        let result = await liveCursor(start)
        if !result.isAuthoritative { cursorAPIRetryAt = now.addingTimeInterval(Self.cursorAPIBackoff) }
        return result.entries
    }

    /// 꺼져 있던 날을 거슬러 읽는 최대 일 수. Claude Code 가 기본으로 30일 지난 대화 기록을 지우므로 그보다 앞은 읽을 게 없다.
    static let catchUpDays = 30

    /// since: 적립 원장 날짜(`claimedDate`). 오늘보다 앞이면 그날부터 어제까지의 날짜별 합계도 `earlier`로 돌려준다
    /// (앱이 꺼져 있던 날·자정 직전 몫을 `Game.claim`이 적립).
    /// detail: 오늘 provider별 입력·출력·캐시 합계 (사용량 화면)
    func read(since: String? = nil, now: Date = Date())
        async -> (date: String, byProvider: [String: Int], earlier: [String: [String: Int]], detail: [String: TokenSum]) {
        let today = LocalUsageReader.localDayFormatter().string(from: now)
        let start = Self.start(since: since, now: now)
        let cursor = await cursorEntries(modifiedSince: start, now: now)
        var earlier: [String: [String: Int]] = [:], detail: [String: TokenSum] = [:]
        for (provider, entries) in others(since: start, claude: claudeEntries(modifiedSince: start), cursor: cursor) {
            detail[provider.rawValue] = TokenSum(Self.bucket(entries, day: today))
            for (day, total) in Self.totalsByDay(entries, before: today) { earlier[day, default: [:]][provider.rawValue] = total }
        }
        return (today, detail.mapValues(\.total), earlier, detail)
    }

    /// Claude·Cursor 는 받은 것, 나머지는 `otherLogs` 로 읽은 provider별 기록
    private func others(since start: Date, claude: [LocalUsageReader.Entry], cursor: [LocalUsageReader.Entry])
        -> [(Provider, [LocalUsageReader.Entry])] {
        [(.claude, claude)] + otherLogs(start) + [(.cursor, cursor)]
    }

    /// Codex·Gemini·Grok·Pi·oh-my-pi 로그를 이 Mac 의 기본 위치에서 바로 읽는다
    static func localOtherLogs(since start: Date) -> [(Provider, [LocalUsageReader.Entry])] {
        [
            (.codex, LocalUsageReader.codexEntries(modifiedSince: start)),
            (.gemini, LocalUsageReader.geminiEntries(modifiedSince: start)),
            (.grok, LocalUsageReader.grokEntries(modifiedSince: start)),
            (.pi, LocalUsageReader.piEntries(modifiedSince: start)),
            (.omp, LocalUsageReader.ompEntries(modifiedSince: start)),
        ]
    }

    /// 사용량 화면이 읽는 지난 날짜 수. 31일이면 오늘이 31일이어도 이번 달 전체가 들어간다.
    static let historyDays = 31
    /// 오늘보다 앞 날짜는 다시 바뀌지 않으므로 날이 바뀔 때까지 한 번 읽은 것을 쓴다
    private var past: (today: String, days: UsageByDay)?

    /// 오늘보다 앞 `historyDays`일의 날짜별 합계 (오늘 몫은 `read`의 detail).
    /// 지난 날은 바뀌지 않으므로 `historyFile`에 두고, 파일에 없는 날만 로그에서 읽는다
    /// (31일 치 Claude 로그는 수백 MB라 처음 한 번은 수십 초 걸린다. 그 뒤로는 하루에 하루치만).
    /// Claude 는 파일 캐시를 쓰지 않고 따로 읽는다(캐시는 오늘 읽는 범위만 들고 있어야 매분 읽기가 가볍다).
    func pastDays(now: Date = Date()) async -> UsageByDay {
        let fmt = LocalUsageReader.localDayFormatter(), cal = Calendar.current
        let today = fmt.string(from: now)
        if let past, past.today == today { return past.days }
        let wanted = (1...Self.historyDays).compactMap {
            cal.date(byAdding: .day, value: -$0, to: cal.startOfDay(for: now)).map(fmt.string)
        }
        let saved = historyFile.flatMap { try? JSONDecoder().decode(UsageByDay.self, from: Data(contentsOf: $0)) } ?? [:]
        var days = saved.filter { wanted.contains($0.key) }
        let missing = Set(wanted.filter { days[$0] == nil })
        if let oldest = missing.min(), let start = fmt.date(from: oldest) {
            let claude = LocalUsageReader.claudeEntries(modifiedSince: start, roots: claudeRoots ?? LocalUsageReader.claudeProjectRoots)
            let cursor = await cursorEntries(modifiedSince: start, now: now)
            var found: [String: [String: LocalUsageReader.Bucket]] = [:]
            for (provider, entries) in others(since: start, claude: claude, cursor: cursor) {
                for e in entries where missing.contains(e.localDay) { found[e.localDay, default: [:]][provider.rawValue, default: .init()].add(e) }
            }
            for day in missing { days[day] = found[day]?.mapValues(TokenSum.init) ?? [:] }
            if let historyFile {
                try? FileManager.default.createDirectory(at: historyFile.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? JSONEncoder().encode(days).write(to: historyFile, options: .atomic)
            }
        }
        past = (today, days)
        return days
    }

    /// from 날짜(포함)부터 through 날짜(포함)까지 모든 provider 의 토큰·비용 합
    static func total(_ days: UsageByDay, from: Date, through: Date) -> (tokens: Int, cost: Double) {
        let fmt = LocalUsageReader.localDayFormatter()
        let a = fmt.string(from: from), b = fmt.string(from: through)
        var tokens = 0, cost = 0.0
        for (day, byProvider) in days where day >= a && day <= b {
            for bucket in byProvider.values { tokens += bucket.total; cost += bucket.cost }
        }
        return (tokens, cost)
    }

    /// 오늘·이번 주·이번 달(오늘 포함) 합 (사용량 화면·업무 모드 요약)
    static func periods(_ days: UsageByDay, now: Date)
        -> (today: (tokens: Int, cost: Double), week: (tokens: Int, cost: Double), month: (tokens: Int, cost: Double)) {
        let cal = Calendar.current
        func since(_ unit: Calendar.Component) -> (tokens: Int, cost: Double) {
            total(days, from: cal.dateInterval(of: unit, for: now)?.start ?? now, through: now)
        }
        return (total(days, from: now, through: now), since(.weekOfYear), since(.month))
    }

    /// 읽기 시작 시각: 원장 날짜의 0시(오늘보다 뒤면 오늘, `catchUpDays`보다 앞이면 그만큼만).
    static func start(since: String?, now: Date) -> Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        guard let since, let day = LocalUsageReader.localDayFormatter().date(from: since) else { return today }
        let oldest = cal.date(byAdding: .day, value: -catchUpDays, to: today) ?? today
        return min(max(cal.startOfDay(for: day), oldest), today)
    }

    /// 그날 기록의 합. 비용은 PokeTokenBar 와 같은 계산(기록된 비용 우선, 없으면 ModelPricing 추정).
    static func bucket(_ entries: [LocalUsageReader.Entry], day: String) -> LocalUsageReader.Bucket {
        var b = LocalUsageReader.Bucket()
        for e in entries where e.localDay == day { b.add(e) }
        return b
    }

    /// 오늘보다 앞 날짜별 토큰 합계 (`bucket`과 같은 계산)
    static func totalsByDay(_ entries: [LocalUsageReader.Entry], before today: String) -> [String: Int] {
        Dictionary(grouping: entries.filter { $0.localDay < today }, by: \.localDay)
            .mapValues { bucket($0, day: $0[0].localDay).total }
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
