#if os(Linux)
import Foundation
import Testing
@testable import YugiTokenBar

@Suite struct LinuxShellTests {
    @Test func midnightRetainsSampleDayUntilANewReadArrives() throws {
        let formatter = LocalUsageReader.localDayFormatter()
        let sampleDay = "2026-10-19"
        let nextDay = try #require(formatter.date(from: "2026-10-20"))
        let sameDay = try #require(formatter.date(from: sampleDay))
        var snapshot = LinuxSnapshot(game: Game(db: makeDB([[(1, 1)]]), state: GameState()))
        snapshot.todayDate = sampleDay
        var detail = TokenSum(); detail.input = 250_000
        snapshot.todayDetail = [Provider.claude.rawValue: detail]
        #expect(snapshot.usageHeading(now: sameDay) == L("오늘 %@", .text("250K")))
        #expect(snapshot.usageHeading(now: nextDay) == L("%@ 사용량 %@", .text(sampleDay), .text("250K")))
        snapshot.todayDate = "2026-10-20"
        #expect(snapshot.usageHeading(now: nextDay) == L("오늘 %@", .text("250K")))
    }
}
#endif
