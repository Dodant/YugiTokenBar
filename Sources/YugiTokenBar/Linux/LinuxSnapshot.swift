#if os(Linux)
import Foundation

struct LinuxUsageSnapshot: Sendable, Equatable {
    var date: String
    var byProvider: [String: Int] = [:]
    var earlier: [String: [String: Int]] = [:]
    var detail: [String: TokenSum] = [:]
}

struct LinuxOpening: Identifiable, Sendable, Equatable {
    var id = UUID()
    var pulls: [Pull]
    var title: String
    var pack: Int? = nil
    var freePack = false
}

struct LinuxSnapshot: Sendable, Equatable {
    var game: Game
    var opening: LinuxOpening?
    var todayDate: String?
    var todayDetail: [String: TokenSum] = [:]
    var history: UsageByDay?
    var historyDate: String?
    var refreshing = false
    var loadingHistory = false
    var usageError: String?
    var historyError: String?
    var saveError: String?
    var dirty = false
    var revision: UInt64 = 0

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.game.state == rhs.game.state && lhs.opening == rhs.opening &&
        lhs.todayDate == rhs.todayDate && lhs.todayDetail == rhs.todayDetail &&
        lhs.history == rhs.history && lhs.historyDate == rhs.historyDate &&
        lhs.refreshing == rhs.refreshing && lhs.loadingHistory == rhs.loadingHistory &&
        lhs.usageError == rhs.usageError && lhs.historyError == rhs.historyError &&
        lhs.saveError == rhs.saveError && lhs.dirty == rhs.dirty
    }
}

struct LinuxUsageService: Sendable {
    var read: @Sendable (String, Date) async throws -> LinuxUsageSnapshot
    var history: @Sendable (Date) async throws -> UsageByDay

    static func live(reader: TodayUsageReader = TodayUsageReader()) -> Self {
        Self(read: { since, now in
            let value = await reader.read(since: since, now: now)
            return LinuxUsageSnapshot(date: value.date, byProvider: value.byProvider,
                                      earlier: value.earlier, detail: value.detail)
        }, history: { await reader.pastDays(now: $0) })
    }
}

#endif
