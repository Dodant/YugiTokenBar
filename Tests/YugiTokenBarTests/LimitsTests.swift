import Foundation
import Testing
@testable import YugiTokenBar

@Suite struct LimitsTests {
    #if os(macOS)
    @Test func claudeMetersIncludeModelScopedWeekly() throws {
        let json = #"""
        {"five_hour":{"utilization":50,"resets_at":"2026-10-01T09:00:00Z"},
         "seven_day":{"utilization":52.4,"resets_at":"2026-10-05T00:00:00Z"},
         "limits":[{"kind":"session","percent":50},{"kind":"weekly_all","percent":52},
                   {"kind":"weekly_scoped","percent":65,"scope":{"model":{"display_name":"Fable"}}}]}
        """#
        let status = try JSONDecoder().decode(LimitStatus.self, from: Data(json.utf8))
        let meters = UsageView.claudeMeters(status)
        #expect(meters.map(\.label) == ["5시간", "주간", "Fable"])
        #expect(meters.map(\.percent) == [50, 52.4, 65])
    }
    #endif

    #if os(macOS)
    /// 신형 limits[] 만 오면 session → "5시간", weekly_all → "주간", 나머지는 모델명. 위 줄 초기화 시각은 session 의 것
    @MainActor @Test func claudeMetersFromNewLimitsOnly() throws {
        let json = #"""
        {"limits":[{"kind":"session","percent":50,"resets_at":"2026-10-01T09:00:00Z"},
                   {"kind":"weekly_all","percent":52,"resets_at":"2026-10-05T00:00:00Z"},
                   {"kind":"weekly_scoped","percent":65,"scope":{"model":{"display_name":"Fable"}}}]}
        """#
        let status = try JSONDecoder().decode(LimitStatus.self, from: Data(json.utf8))
        #expect(UsageView.claudeMeters(status).map(\.label) == ["5시간", "주간", "Fable"])
        let session = try #require(status.limits?.first?.resetDate)
        #expect(UsageView.claudeReset(status) == session)
    }
    #endif

    #if os(macOS)
    @Test func resetTextInKorean() {
        let now = Date(timeIntervalSince1970: 0)
        #expect(UsageView.resetText(now.addingTimeInterval(48 * 60), now: now) == "48분 후 초기화")
        #expect(UsageView.resetText(now.addingTimeInterval(126 * 60), now: now) == "2시간 6분 후 초기화")
        #expect(UsageView.resetText(now.addingTimeInterval(-60), now: now) == "0분 후 초기화")
    }
    #endif

    @Test func shortCoinsKeepsDecimalOnlyForOneDigit() {
        #expect(shortCoins(2_400) == 2_400.formatted())
        #expect(shortCoins(34_200) == "34K")
        #expect(shortCoins(293_300) == "293K")
        #expect(shortCoins(2_400_000) == "2.4M")
        #expect(shortCoins(1_000_000) == "1M")
        #expect(shortCoins(12_345_678) == "12M")
    }
}
