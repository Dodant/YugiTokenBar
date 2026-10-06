import Foundation

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

    func read(now: Date = Date()) async -> (date: String, byProvider: [String: Int], cost: [String: Double]) {
        let start = Calendar.current.startOfDay(for: now)
        let today = LocalUsageReader.localDayFormatter().string(from: now)
        // 아래는 Claude 를 캐시에서 읽는 것만 빼면 TodayUsage.read 와 같다
        let cursor = AppEnv.allowsLiveLimitsFetch
            ? await LocalAdditionalUsageReader.cursorEntriesAsync(modifiedSince: start).entries
            : LocalAdditionalUsageReader.cursorEntries(modifiedSince: start).entries
        var tokens: [String: Int] = [:], cost: [String: Double] = [:]
        for (provider, entries) in [
            ("claude_code", claudeEntries(modifiedSince: start)),
            ("codex", LocalUsageReader.codexEntries(modifiedSince: start)),
            ("gemini", LocalUsageReader.geminiEntries(modifiedSince: start)),
            ("grok", LocalUsageReader.grokEntries(modifiedSince: start)),
            ("pi", LocalUsageReader.piEntries(modifiedSince: start)),
            ("omp", LocalUsageReader.ompEntries(modifiedSince: start)),
            ("cursor", cursor),
        ] {
            let b = TodayUsage.bucket(entries, day: today)
            tokens[provider] = b.total
            cost[provider] = b.cost
        }
        return (today, tokens, cost)
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
