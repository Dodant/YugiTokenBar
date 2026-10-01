import Foundation
import Testing
@testable import YugiTokenBar

@Suite struct LimitsTests {
    @Test func claudeMetersIncludeModelScopedWeekly() throws {
        let json = #"""
        {"five_hour":{"utilization":50,"resets_at":"2026-10-01T09:00:00Z"},
         "seven_day":{"utilization":52.4,"resets_at":"2026-10-05T00:00:00Z"},
         "limits":[{"kind":"session","percent":50},{"kind":"weekly_all","percent":52},
                   {"kind":"weekly_scoped","percent":65,"scope":{"model":{"display_name":"Fable"}}}]}
        """#
        let status = try JSONDecoder().decode(LimitStatus.self, from: Data(json.utf8))
        let meters = UsageView.claudeMeters(status)
        #expect(meters.map(\.label) == ["5h", "주", "Fable"])
        #expect(meters.map(\.percent) == [50, 52.4, 65])
    }

    @Test func resetTextInKorean() {
        let now = Date(timeIntervalSince1970: 0)
        #expect(UsageView.resetText(now.addingTimeInterval(48 * 60), now: now) == "48분 후 초기화")
        #expect(UsageView.resetText(now.addingTimeInterval(126 * 60), now: now) == "2시간 6분 후 초기화")
        #expect(UsageView.resetText(now.addingTimeInterval(-60), now: now) == "0분 후 초기화")
    }
}
