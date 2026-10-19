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

struct LinuxPendingImport: Sendable, Equatable {
    var envelope: SaveEnvelope
    var fileName: String
}

struct LinuxSnapshot: Sendable, Equatable {
    var game: Game
    var opening: LinuxOpening?
    var dexPack: Int?
    var dexCard: Int?
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
    var pendingImport: LinuxPendingImport?
    var transferMessage: String?
    var transferError: String?
    var revision: UInt64 = 0

    /// Keep the sample's calendar day attached to its provider totals across midnight.
    func usageHeading(now: Date = Date()) -> String {
        let count = shortTokens(todayDetail.values.reduce(0) { $0 + $1.total })
        let today = LocalUsageReader.localDayFormatter().string(from: now)
        if let sampled = todayDate, sampled != today {
            return L("%@ 사용량 %@", .text(sampled), .text(count))
        }
        return L("오늘 %@", .text(count))
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.game.state == rhs.game.state && lhs.opening == rhs.opening &&
        lhs.dexPack == rhs.dexPack && lhs.dexCard == rhs.dexCard &&
        lhs.todayDate == rhs.todayDate && lhs.todayDetail == rhs.todayDetail &&
        lhs.history == rhs.history && lhs.historyDate == rhs.historyDate &&
        lhs.refreshing == rhs.refreshing && lhs.loadingHistory == rhs.loadingHistory &&
        lhs.usageError == rhs.usageError && lhs.historyError == rhs.historyError &&
        lhs.saveError == rhs.saveError && lhs.dirty == rhs.dirty &&
        lhs.pendingImport == rhs.pendingImport && lhs.transferMessage == rhs.transferMessage &&
        lhs.transferError == rhs.transferError
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
