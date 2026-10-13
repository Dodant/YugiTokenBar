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
/// Claude·Codex·Gemini·Grok·Pi·oh-my-pi 로그는 `LocalUsageCache`(PokeTokenBar)가 파일마다 (경로, 수정 시각, 크기)가
/// 그대로면 다시 파싱하지 않고, 파싱 결과를 세이브 폴더 `usage-cache.json`에 둬 다음 실행에도 쓴다(실앱만).
/// 이번 실행에서 바뀌는 것이 보인 Claude 세션 파일(쓰는 중)은 여기서 지난번 읽은 위치 뒤에 붙은 줄만 읽는다(`claudeTails`).
/// 로컬 Cursor DB(`state.vscdb`)는 행이 덧붙기만 해서 지난번 rowid 뒤만 읽어 합친다.
/// Cursor 대시보드 API는 실패하면 30분 백오프(그동안 로컬 `state.vscdb`만 읽는다). 백오프 끝 시각은 실앱에서 UserDefaults에 둬 다시 켜도 지킨다.
// ponytail: Codex·Gemini 등 다른 provider 의 쓰는 중인 파일은 여전히 통째로 다시 읽는다. 무거워지면 Claude 처럼 붙은 줄만 읽는다
actor TodayUsageReader {
    /// 오늘 몫을 읽는 파일별 캐시 (지난 날짜 `pastDays`는 쓰지 않는다)
    private let cache: LocalUsageCache
    /// 테스트용. nil 이면 `LocalUsageReader.claudeProjectRoots`
    private let claudeRoots: [URL]?
    /// 로컬 Cursor DB 에서 마지막으로 읽은 것: 읽기 시작 시각, 그때까지의 기록, DB 마다 마지막 rowid
    private var cursorLocal: (start: Date, entries: [LocalUsageReader.Entry], marks: [String: Int64])?

    /// 대시보드 API 가 실패하면(토큰 없음·HTTP 오류) 이만큼은 다시 부르지 않고 로컬 `state.vscdb`만 읽는다. 매분 실패하는 네트워크 호출을 막는다.
    static let cursorAPIBackoff: TimeInterval = 30 * 60
    private var cursorAPIRetryAt: Date
    /// `cursorAPIRetryAt`을 두는 곳. 실앱만(테스트·개발 실행은 nil)
    private let backoffStore: UserDefaults?
    private static let retryAtKey = "cursorAPIRetryAt"
    /// 대시보드 API 경로. 실앱·`PTB_PARITY=1`(`AppEnv.allowsLiveLimitsFetch`)에서만 있고, 테스트는 가짜를 넣는다.
    private let liveCursor: (@Sendable (Date) async -> LocalAdditionalUsageReader.CursorLoadResult)?

    /// 지난 날짜별 합계 파일. nil 이면 디스크에 두지 않는다
    private let historyFile: URL?
    /// Claude·Cursor 밖 provider 의 로그 읽기. 테스트는 빈 결과를 넣어 이 Mac 의 실제 로그를 읽지 않는다
    private let otherLogs: @Sendable (Date) -> [(Provider, [LocalUsageReader.Entry])]

    /// cache: nil 이면 `claudeRoots`만 바꾼 기본 캐시 (디스크 저장은 실앱만, `AppEnv.persistsToUserLocation`)
    init(claudeRoots: [URL]? = nil, cache: LocalUsageCache? = nil,
         historyFile: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("YugiTokenBar/usage-days.json"),
         liveCursor: (@Sendable (Date) async -> LocalAdditionalUsageReader.CursorLoadResult)? =
            AppEnv.allowsLiveLimitsFetch ? { @Sendable in await LocalAdditionalUsageReader.cursorEntriesAsync(modifiedSince: $0) } : nil,
         otherLogs: @escaping @Sendable (Date) -> [(Provider, [LocalUsageReader.Entry])] = TodayUsageReader.localOtherLogs,
         backoffStore: UserDefaults? = AppEnv.isBundledApp ? .standard : nil) {
        self.claudeRoots = claudeRoots
        self.cache = cache ?? LocalUsageCache(claudeRoots: claudeRoots)
        self.historyFile = historyFile
        self.liveCursor = liveCursor
        self.otherLogs = otherLogs
        self.backoffStore = backoffStore
        cursorAPIRetryAt = backoffStore?.object(forKey: Self.retryAtKey) as? Date ?? .distantPast
    }

    /// Cursor: 대시보드 API 가 있으면 그것, 실패(`isAuthoritative == false`)하면 `cursorAPIBackoff` 동안 로컬만.
    func cursorEntries(modifiedSince start: Date, now: Date) async -> [LocalUsageReader.Entry] {
        guard let liveCursor, now >= cursorAPIRetryAt else { return localCursorEntries(modifiedSince: start) }
        let result = await liveCursor(start)
        if !result.isAuthoritative {
            cursorAPIRetryAt = now.addingTimeInterval(Self.cursorAPIBackoff)
            backoffStore?.set(cursorAPIRetryAt, forKey: Self.retryAtKey)
        }
        return result.entries
    }

    /// 로컬 `state.vscdb`: 읽기 시작 시각이 지난번과 같으면 그때의 rowid 뒤만 읽어 지난 기록과 합친다.
    /// DB 를 새로 쓰거나 줄여 rowid 가 거꾸로 가면(`didReset`) 처음부터 읽은 것만 쓴다.
    /// `roots`: 테스트용. nil 이면 Cursor 기본 위치
    func localCursorEntries(modifiedSince start: Date, roots: [URL]? = nil) -> [LocalUsageReader.Entry] {
        let previous = cursorLocal.flatMap { $0.start == start ? $0 : nil }
        let loaded = LocalAdditionalUsageReader.cursorEntries(modifiedSince: start, afterRowIDByPath: previous?.marks, roots: roots)
        let entries = previous.map { loaded.didReset ? loaded.entries : LocalUsageReader.dedupKeepMax($0.entries + loaded.entries) }
            ?? loaded.entries
        cursorLocal = (start, entries, loaded.highWaterByPath)
        return entries
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
        let logs: [(Provider, [LocalUsageReader.Entry])] = [
            (.claude, await claudeEntries(modifiedSince: start)),
            (.codex, await cache.codexEntries(modifiedSince: start)),
            (.gemini, await cache.geminiEntries(modifiedSince: start)),
            (.grok, await cache.grokEntries(modifiedSince: start)),
            (.pi, await cache.piEntries(modifiedSince: start)),
            (.omp, await cache.ompEntries(modifiedSince: start)),
            (.cursor, await cursorEntries(modifiedSince: start, now: now)),
        ]
        var earlier: [String: [String: Int]] = [:], detail: [String: TokenSum] = [:]
        for (provider, entries) in logs {
            detail[provider.rawValue] = TokenSum(Self.bucket(entries, day: today))
            for (day, total) in Self.totalsByDay(entries, before: today) { earlier[day, default: [:]][provider.rawValue] = total }
        }
        return (today, detail.mapValues(\.total), earlier, detail)
    }

    /// 지난 날짜(`pastDays`)용: Claude·Cursor 는 받은 것, 나머지는 `otherLogs` 로 읽은 provider별 기록
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

    /// 쓰는 중인 Claude 파일: 읽은 바이트 위치(마지막 줄바꿈 뒤), 그때까지 파일 안에서 dedup 한 기록, 마지막 비용 원장
    struct ClaudeTail {
        var offset = 0
        var entries: [LocalUsageReader.Entry] = []
        var costState: LocalUsageReader.ClaudeCostState?
    }
    private var claudeTails: [String: ClaudeTail] = [:]
    /// 이번 실행에서 지난번 본 Claude 파일의 (수정 시각, 크기). 이것이 바뀐 파일부터 `claudeTails`로 읽는다
    private var claudeSeen: [String: (Date, Int)] = [:]

    /// `LocalUsageReader.claudeEntries(modifiedSince:roots:)` 와 같은 결과.
    /// 바뀌지 않는 파일은 `LocalUsageCache`(디스크까지)에서, 이번 실행에서 바뀐 파일은 붙은 줄만 읽어서.
    func claudeEntries(modifiedSince start: Date) async -> [LocalUsageReader.Entry] {
        var tails: [String: ClaudeTail] = [:], seen: [String: (Date, Int)] = [:], hot: [LocalUsageReader.Entry] = []
        for root in claudeRoots ?? LocalUsageReader.claudeProjectRoots {
            for url in LocalUsageReader.jsonlFiles(in: root, modifiedSince: start) {
                guard let v = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                      let mtime = v.contentModificationDate else { continue }
                let sig = (mtime, v.fileSize ?? 0)
                seen[url.path] = sig
                guard var tail = claudeTails[url.path] ?? claudeSeen[url.path].flatMap({ $0 == sig ? nil : ClaudeTail() })
                else { continue }
                Self.readTail(url, into: &tail)
                tails[url.path] = tail
                hot += tail.costState.map { LocalUsageReader.applyReportedCost(tail.entries, $0) } ?? tail.entries
            }
        }
        claudeTails = tails
        claudeSeen = seen
        let cold = await cache.claudeEntries(modifiedSince: start, skipping: Set(tails.keys))
        return LocalUsageReader.dedupKeepMax(cold + hot)
    }

    /// `tail.offset` 뒤에 붙은 완성된 줄만 `LocalUsageReader.parseClaudeFile`과 같은 규칙으로 읽어 더한다.
    /// 파일이 줄었으면(새로 씀) 처음부터. 줄바꿈이 없는 마지막 줄은 아직 쓰는 중이라 다음에 읽는다.
    static func readTail(_ url: URL, into tail: inout ClaudeTail) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return }
        if end < tail.offset { tail = ClaudeTail() }
        guard (try? handle.seek(toOffset: UInt64(tail.offset))) != nil, let data = try? handle.readToEnd(),
              let cut = data.lastIndex(of: UInt8(ascii: "\n")) else { return }
        tail.offset += cut - data.startIndex + 1
        let fmt = LocalUsageReader.localDayFormatter(), session = LocalUsageReader.claudeSessionID(forTranscript: url)
        var new: [LocalUsageReader.Entry] = []
        for line in String(decoding: data[..<cut], as: UTF8.self).split(separator: "\n") {
            autoreleasepool {
                if line.contains("\"cost-state\"") {
                    if let s = LocalUsageReader.parseClaudeCostStateLine(String(line)) { tail.costState = s }
                } else if line.contains("\"usage\""), line.contains("\"assistant\""),
                          var e = LocalUsageReader.parseClaudeLine(String(line), fmt: fmt) {
                    e.sessionID = session
                    new.append(e)
                }
            }
        }
        if !new.isEmpty { tail.entries = LocalUsageReader.dedupKeepMax(tail.entries + new) }
    }
}
