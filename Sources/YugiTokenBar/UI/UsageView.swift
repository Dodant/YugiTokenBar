import SwiftUI

/// Claude Code·Codex 공식 한도(5시간·주간·모델별 주간) + 오늘 토큰·비용. 누르면 사용량 화면(`UsageDetailView`)으로 간다.
/// 그 밖의 에이전트(Gemini·Grok·Pi·oh-my-pi·Cursor)는 오늘 쓴 것만 토큰·비용 한 줄로 보인다.
struct UsageView: View {
    @Environment(AppModel.self) private var model
    @State private var hover = false
    /// 업무 모드면 카드 줄(최근 획득)이 빠진 자리에 합계 요약을 더 보인다
    @Environment(\.workMode) private var workMode

    var body: some View {
        let claude = model.claudeLimits
        let codex = model.codexLimits
        let loading = model.fetchingLimits
        // 메뉴 줄처럼 마우스를 올리면 배경이 생기고, 누르면 사용량 화면으로 넘어간다
        Button { model.screen = .usage } label: { VStack(alignment: .leading, spacing: 12) {
            if workMode { WorkSummary() }
            ForEach(Self.agents, id: \.id) { p in
                let today = model.todayDetail[p.id.rawValue] ?? .init(), tokens = today.total, cost = today.cost
                switch p.id {
                case .claude:
                    ProviderUsageRow(name: p.name, symbol: p.symbol, tint: p.tint, tokens: tokens, cost: cost,
                                     reset: claude.flatMap(Self.claudeReset), meters: claude.map(Self.claudeMeters) ?? [], loading: loading)
                case .codex:
                    ProviderUsageRow(name: p.name, symbol: p.symbol, tint: p.tint, tokens: tokens, cost: cost,
                                     reset: codex?.primary?.resetDate, meters: codex.map(Self.codexMeters) ?? [], loading: loading)
                default:
                    if tokens > 0 {
                        ProviderUsageRow(name: p.name, symbol: p.symbol, tint: p.tint, tokens: tokens, cost: cost, reset: nil, meters: nil)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .background(hover ? AnyShapeStyle(.fill.tertiary) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 10)) }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityHint("눌러서 사용량을 자세히 봐요")
    }

    /// 표시 순서. Claude·Codex 는 공식 한도가 있어 늘 보인다
    typealias Agent = (id: Provider, name: String, symbol: String, tint: Color)
    static let agents: [Agent] = [
        (.claude, "Claude", "staroflife.fill", .orange),
        (.codex, "Codex", "hexagon.fill", .teal),
        (.gemini, "Gemini", "sparkle", .blue),
        (.grok, "Grok", "bolt.fill", .gray),
        (.pi, "Pi", "circle.hexagongrid.fill", .purple),
        (.omp, "oh-my-pi", "circle.hexagongrid", .indigo),
        (.cursor, "Cursor", "cursorarrow.rays", .mint),
    ]

    static func claudeMeters(_ s: LimitStatus) -> [Meter] {
        var meters: [Meter] = []
        if let u = s.fiveHour?.utilization { meters.append(Meter(label: String(localized: "5시간"), percent: u, resetsAt: s.fiveHour?.resetDate)) }
        if let u = s.sevenDay?.utilization { meters.append(Meter(label: String(localized: "주간"), percent: u, resetsAt: s.sevenDay?.resetDate)) }
        for e in s.scopedLimitEntries {
            guard let p = e.percent else { continue }
            // 신형 응답만 오면 session·weekly_all 도 여기로 온다
            let label = switch e.kind {
            case "session": String(localized: "5시간")
            case "weekly_all": String(localized: "주간")
            default: e.scope?.model?.displayName ?? String(localized: "모델")
            }
            meters.append(Meter(label: label, percent: p, resetsAt: e.resetDate))
        }
        return meters
    }

    /// 위 줄 5시간 창 초기화 시각. 신형 응답만 오면 session 엔트리의 것.
    static func claudeReset(_ s: LimitStatus) -> Date? {
        s.fiveHour?.resetDate ?? s.limits?.first { $0.kind == "session" }?.resetDate
    }

    /// "48분 후 초기화", "2시간 6분 후 초기화"
    static func resetText(_ date: Date, now: Date = Date()) -> String {
        let mins = max(0, Int(date.timeIntervalSince(now) / 60))
        let h = mins / 60, m = mins % 60
        if h >= 24 { return String(localized: "\(h / 24)일 \(h % 24)시간 후 초기화") }
        return h > 0 ? String(localized: "\(h)시간 \(m)분 후 초기화") : String(localized: "\(m)분 후 초기화")
    }

    static func codexMeters(_ s: CodexRateLimitSnapshot) -> [Meter] {
        [s.primary.map { Meter(label: String(localized: "5시간"), percent: Double($0.usedPercent), resetsAt: $0.resetDate) },
         s.secondary.map { Meter(label: String(localized: "주간"), percent: Double($0.usedPercent), resetsAt: $0.resetDate) }].compactMap { $0 }
    }
}

struct Meter {
    let label: String
    let percent: Double
    /// 초기화 시각 (모르면 nil). 지난 한도는 파트너 상태에서 뺀다.
    var resetsAt: Date? = nil
}

struct ProviderUsageRow: View {
    let name: String
    let symbol: String
    let tint: Color
    let tokens: Int
    let cost: Double
    let reset: Date?
    /// nil 이면 공식 한도를 읽지 않는 provider (한도 줄 없음)
    let meters: [Meter]?
    /// 한도를 읽는 중이면 초기화 시각 자리에 도는 표시
    var loading = false
    /// 한도를 아직 못 읽었을 때 문구 (메뉴 줄은 누르라고, 사용량 화면은 새로고침하라고)
    var emptyText: LocalizedStringKey = "한도를 보려면 누르세요"

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
                    if loading, meters != nil {
                        ProgressView().controlSize(.mini)
                    } else if let reset {
                        Text(UsageView.resetText(reset)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(shortTokens(tokens)) · \(String(format: "$%.2f", cost))")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                if let meters, meters.isEmpty {
                    Text(loading ? "한도 불러오는 중…" : emptyText).font(.caption).foregroundStyle(.secondary)
                } else if let meters {
                    HStack(spacing: 10) {
                        ForEach(Array(meters.enumerated()), id: \.offset) { MeterView(meter: $0.element) }  // 라벨이 겹쳐도 안전하게
                    }
                }
            }
        }
    }
}

struct MeterView: View {
    let meter: Meter
    /// 막대 폭. 이름이 "5시간"·"주간"이라 "5h"·"주" 때(30)보다 줄여 Claude 한 줄(한도 3개)이 패널 폭에 들어가게
    private static let barWidth = 24.0

    var body: some View {
        let p = min(100, max(0, meter.percent))
        let color: Color = p >= 85 ? Palette.danger : p >= 60 ? Palette.warning : .primary
        HStack(spacing: 4) {
            Text(meter.label).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            Capsule().fill(.quaternary)
                .frame(width: Self.barWidth, height: 4)
                .overlay(alignment: .leading) {
                    Capsule().fill(p >= 60 ? color : .secondary).frame(width: Self.barWidth * p / 100, height: 4)
                }
            Text("\(Int(p.rounded()))%").font(.caption.weight(.medium)).monospacedDigit().foregroundStyle(color)
        }
    }
}

/// 업무 모드 사용량 칸 맨 위: 오늘·이번 주·이번 달 합계와 최근 14일 막대 (모든 에이전트 합, 오늘은 강조색).
/// 지난 날짜는 사용량 화면과 같은 것(`AppModel.pastUsage`, 디스크 캐시)을 읽는다.
private struct WorkSummary: View {
    @Environment(AppModel.self) private var model
    private static let barHeight = 18.0

    var body: some View {
        let now = Date(), cal = Calendar.current
        let usage = model.usageByDay
        let today = TodayUsageReader.total(usage, from: now, through: now)
        let week = TodayUsageReader.total(usage, from: cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now, through: now)
        let month = TodayUsageReader.total(usage, from: cal.dateInterval(of: .month, for: now)?.start ?? now, through: now)
        let days = UsageDetailView.days(usage, now: now, count: 14)
        let peak = days.map(\.tokens).max() ?? 0
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("오늘").font(.caption).foregroundStyle(.secondary)
                Text(shortTokens(today.tokens)).font(.title3.weight(.semibold))
                Text(UsageDetailView.costText(today.cost)).font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .lineLimit(1)
            .monospacedDigit()
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(days.enumerated()), id: \.element.id) { i, d in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(i == days.count - 1 ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                        .frame(height: peak > 0 && d.tokens > 0 ? max(2, Self.barHeight * Double(d.tokens) / Double(peak)) : 1)
                        .opacity(d.tokens > 0 ? 1 : 0.5)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: Self.barHeight, alignment: .bottom)
            .opacity(model.pastUsage == nil ? 0.4 : 1)
            .accessibilityHidden(true)
            HStack(spacing: 4) {
                Text("이번 주").foregroundStyle(.secondary)
                Text(shortTokens(week.tokens)).fontWeight(.medium)
                Text(UsageDetailView.costText(week.cost)).foregroundStyle(.secondary)
                Spacer()
                Text("이번 달").foregroundStyle(.secondary)
                Text(shortTokens(month.tokens)).fontWeight(.medium)
                Text(UsageDetailView.costText(month.cost)).foregroundStyle(.secondary)
            }
            .font(.caption)
            .lineLimit(1)
            .monospacedDigit()
            .redacted(reason: model.pastUsage == nil ? .placeholder : [])
        }
        .task { await model.loadHistory() }
    }
}
