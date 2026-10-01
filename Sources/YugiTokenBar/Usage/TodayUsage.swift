import Foundation

/// 오늘(로컬 날짜) provider별 누적 토큰. 토큰 = input + output + cacheWrite + cacheRead (PokeTokenBar 와 동일).
enum TodayUsage {
    static func read(now: Date = Date()) -> (date: String, byProvider: [String: Int]) {
        let start = Calendar.current.startOfDay(for: now)
        let today = LocalUsageReader.localDayFormatter().string(from: now)
        return (today, [
            "claude_code": total(LocalUsageReader.claudeEntries(modifiedSince: start), day: today),
            "codex": total(LocalUsageReader.codexEntries(modifiedSince: start), day: today),
        ])
    }

    static func total(_ entries: [LocalUsageReader.Entry], day: String) -> Int {
        var sum = 0
        for e in entries where e.localDay == day {
            sum += e.input + e.output + e.cacheWrite + e.cacheRead
        }
        return sum
    }
}
