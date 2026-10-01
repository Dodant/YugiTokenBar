import Foundation

/// 오늘(로컬 날짜) provider별 누적 토큰과 비용. 토큰 = input + output + cacheWrite + cacheRead (PokeTokenBar 와 동일).
enum TodayUsage {
    static let providers = ["claude_code", "codex"]

    static func read(now: Date = Date()) -> (date: String, byProvider: [String: Int], cost: [String: Double]) {
        let start = Calendar.current.startOfDay(for: now)
        let today = LocalUsageReader.localDayFormatter().string(from: now)
        var tokens: [String: Int] = [:], cost: [String: Double] = [:]
        for (provider, entries) in [
            ("claude_code", LocalUsageReader.claudeEntries(modifiedSince: start)),
            ("codex", LocalUsageReader.codexEntries(modifiedSince: start)),
        ] {
            let b = bucket(entries, day: today)
            tokens[provider] = b.total
            cost[provider] = b.cost
        }
        return (today, tokens, cost)
    }

    static func total(_ entries: [LocalUsageReader.Entry], day: String) -> Int {
        bucket(entries, day: day).total
    }

    /// PokeTokenBar 와 같은 비용 계산(기록된 비용 우선, 없으면 ModelPricing 추정).
    static func bucket(_ entries: [LocalUsageReader.Entry], day: String) -> LocalUsageReader.Bucket {
        var b = LocalUsageReader.Bucket()
        for e in entries where e.localDay == day { b.add(e) }
        return b
    }
}
