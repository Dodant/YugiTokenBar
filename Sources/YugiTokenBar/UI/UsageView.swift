import SwiftUI

/// Claude Code·Codex 공식 한도(5시간·주간·모델별 주간) + 오늘 토큰·비용. 누르면 한도를 바로 다시 읽는다.
struct UsageView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let claude = model.claudeLimits
        let codex = model.codexLimits
        VStack(alignment: .leading, spacing: 12) {
            ProviderUsageRow(
                name: "Claude", symbol: "staroflife.fill", tint: .orange,
                tokens: model.todayTokens["claude_code"] ?? 0, cost: model.todayCost["claude_code"] ?? 0,
                reset: claude?.fiveHour?.resetDate,
                meters: claude.map(Self.claudeMeters) ?? [])
            ProviderUsageRow(
                name: "Codex", symbol: "hexagon.fill", tint: .teal,
                tokens: model.todayTokens["codex"] ?? 0, cost: model.todayCost["codex"] ?? 0,
                reset: codex?.primary?.resetDate,
                meters: codex.map(Self.codexMeters) ?? [])
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { model.refreshLimits(userInitiated: true) }
    }

    static func claudeMeters(_ s: LimitStatus) -> [Meter] {
        var meters: [Meter] = []
        if let u = s.fiveHour?.utilization { meters.append(Meter(label: "5h", percent: u)) }
        if let u = s.sevenDay?.utilization { meters.append(Meter(label: "주", percent: u)) }
        for e in s.scopedLimitEntries {
            guard let p = e.percent else { continue }
            meters.append(Meter(label: e.scope?.model?.displayName ?? "모델", percent: p))
        }
        return meters
    }

    /// "48분 후 초기화", "2시간 6분 후 초기화"
    static func resetText(_ date: Date, now: Date = Date()) -> String {
        let mins = max(0, Int(date.timeIntervalSince(now) / 60))
        let h = mins / 60, m = mins % 60
        if h >= 24 { return "\(h / 24)일 \(h % 24)시간 후 초기화" }
        return h > 0 ? "\(h)시간 \(m)분 후 초기화" : "\(m)분 후 초기화"
    }

    static func codexMeters(_ s: CodexRateLimitSnapshot) -> [Meter] {
        [s.primary.map { Meter(label: "5h", percent: Double($0.usedPercent)) },
         s.secondary.map { Meter(label: "주", percent: Double($0.usedPercent)) }].compactMap { $0 }
    }
}

struct Meter {
    let label: String
    let percent: Double
}

private struct ProviderUsageRow: View {
    let name: String
    let symbol: String
    let tint: Color
    let tokens: Int
    let cost: Double
    let reset: Date?
    let meters: [Meter]

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(tint.opacity(0.15), in: .rect(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(name).font(.callout.weight(.semibold))
                    if let reset { Text(UsageView.resetText(reset)).font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Text("\(shortTokens(tokens)) · \(String(format: "$%.2f", cost))")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                if meters.isEmpty {
                    Text("한도 정보 없음 · 눌러서 불러오기").font(.caption).foregroundStyle(.tertiary)
                } else {
                    HStack(spacing: 10) {
                        ForEach(meters, id: \.label) { MeterView(meter: $0) }
                    }
                }
            }
        }
    }
}

private struct MeterView: View {
    let meter: Meter

    var body: some View {
        let p = min(100, max(0, meter.percent))
        let color: Color = p >= 85 ? .red : p >= 60 ? .orange : .primary
        HStack(spacing: 4) {
            Text(meter.label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Capsule().fill(.quaternary)
                .frame(width: 30, height: 4)
                .overlay(alignment: .leading) {
                    Capsule().fill(p >= 60 ? color : .secondary).frame(width: 30 * p / 100, height: 4)
                }
            Text("\(Int(p.rounded()))%").font(.caption.weight(.medium)).monospacedDigit().foregroundStyle(color)
        }
    }
}
