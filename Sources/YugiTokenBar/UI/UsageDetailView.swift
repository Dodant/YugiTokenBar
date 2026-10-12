import SwiftUI

/// 팝오버 안 사용량 화면 (상점처럼 요약 위에 겹쳐 그린다).
/// 오늘 합계, 이번 주·이번 달, 최근 30일 막대(모든 에이전트 합), 에이전트별 오늘 입력·출력·캐시와 공식 한도.
struct UsageDetailView: View {
    @Environment(AppModel.self) private var model
    /// 고른 에이전트 탭 (nil 이면 첫 탭)
    @State private var picked: Provider?
    /// 마우스를 올린 막대의 날짜 (nil 이면 오늘)
    @State private var hoveredDay: String?

    private static let chartDays = 30
    private static let chartHeight = 48.0

    /// byAgent: provider rawValue → 그날 토큰 (고른 탭의 몫을 막대에 칠한다)
    private struct Day { let id: String; let date: Date; let tokens: Int; let cost: Double; let byAgent: [String: Int] }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PanelHeader(title: String(localized: "사용량"), back: { model.screen = .summary }) {
                Button { model.refresh(); model.refreshLimits(userInitiated: true) } label: {
                    Image(systemName: "arrow.clockwise").font(.body.weight(.semibold)).frame(width: 24, height: 24).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(model.fetchingLimits)
                .accessibilityLabel("새로고침")
            }
            ScrollView {
                content.padding(.horizontal, 2)
            }
            .scrollIndicators(.never)
            .frame(maxHeight: .infinity)
            .panelScrollBottom()
        }
        .task {
            model.refreshLimits(userInitiated: true)
            await model.loadHistory()
        }
    }

    private var content: some View {
        let now = Date()
        let cal = Calendar.current
        var usage = model.pastUsage ?? [:]
        usage[LocalUsageReader.localDayFormatter().string(from: now)] = model.todayDetail
        let today = TodayUsageReader.total(usage, from: now, through: now)
        let week = TodayUsageReader.total(usage, from: cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now, through: now)
        let month = TodayUsageReader.total(usage, from: cal.dateInterval(of: .month, for: now)?.start ?? now, through: now)
        let days = Self.days(usage, now: now)
        let agents = UsageView.agents.filter { a in
            a.id == .claude || a.id == .codex || usage.values.contains { ($0[a.id.rawValue]?.total ?? 0) > 0 }
        }
        let agent = agents.first { $0.id == picked } ?? agents[0]

        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("오늘 사용한 토큰").font(.caption).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(shortTokens(today.tokens))
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .contentTransition(.numericText())
                    Text(today.tokens.formatted()).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(Self.costText(today.cost)).font(.callout.weight(.medium))
                }
                .monospacedDigit()
                HStack(spacing: 14) {
                    stat("이번 주", week)
                    stat("이번 달", month)
                }
                .redacted(reason: model.pastUsage == nil ? .placeholder : [])
            }
            chart(days, agent: agent)
            VStack(alignment: .leading, spacing: 10) {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(agents, id: \.id) { a in tab(a.name, selected: a.id == agent.id) { picked = a.id } }
                    }
                }
                .scrollIndicators(.never)
                detail(agent)
            }
        }
    }

    /// 오늘 포함 최근 `chartDays`일 (오래된 날부터)
    private static func days(_ usage: UsageByDay, now: Date) -> [Day] {
        let cal = Calendar.current, fmt = LocalUsageReader.localDayFormatter()
        let today = cal.startOfDay(for: now)
        return (0..<chartDays).reversed().compactMap { back in
            guard let date = cal.date(byAdding: .day, value: -back, to: today) else { return nil }
            let id = fmt.string(from: date)
            let t = TodayUsageReader.total(usage, from: date, through: date)
            return Day(id: id, date: date, tokens: t.tokens, cost: t.cost, byAgent: usage[id]?.mapValues(\.total) ?? [:])
        }
    }

    private func stat(_ label: LocalizedStringKey, _ t: (tokens: Int, cost: Double)) -> some View {
        HStack(spacing: 4) {
            Text(label).foregroundStyle(.secondary)
            Text(shortTokens(t.tokens)).fontWeight(.semibold)
            Text(Self.costText(t.cost)).foregroundStyle(.secondary)
        }
        .font(.caption)
        .monospacedDigit()
    }

    private func chart(_ days: [Day], agent: (id: Provider, name: String, symbol: String, tint: Color)) -> some View {
        let maxTokens = days.map(\.tokens).max() ?? 0
        let shown = days.first { $0.id == hoveredDay } ?? days.last
        let loading = model.pastUsage == nil
        let cal = Calendar.current
        func height(_ n: Int) -> Double { maxTokens > 0 && n > 0 ? max(2, Self.chartHeight * Double(n) / Double(maxTokens)) : 0 }
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("최근 30일").foregroundStyle(.secondary)
                if let shown {
                    Text(shown.date, format: .dateTime.month(.defaultDigits).day().weekday(.abbreviated))
                    Text(shortTokens(shown.tokens)).fontWeight(.semibold)
                    Text(Self.costText(shown.cost)).foregroundStyle(.secondary)
                }
                Spacer()
                if loading {
                    ProgressView().controlSize(.mini)
                } else {
                    Text("최다").foregroundStyle(.secondary)
                    Text(shortTokens(maxTokens)).fontWeight(.semibold)
                }
            }
            .font(.caption)
            .monospacedDigit()
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(days.enumerated()), id: \.element.id) { i, d in
                    let isToday = i == days.count - 1
                    let hovered = d.id == hoveredDay
                    // 주가 바뀌는 날 앞에 가는 선. 날짜는 오늘 라벨과 겹치지 않을 때만
                    let weekStart = i > 0 && cal.component(.weekday, from: d.date) == cal.firstWeekday
                    let label = isToday || (weekStart && i < days.count - 3)
                    let mine = d.byAgent[agent.id.rawValue] ?? 0
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        // 그날 합(회색) 아래쪽에 고른 에이전트 몫을 그 색으로. 쓴 게 없는 날은 바닥선만
                        ZStack(alignment: .bottom) {
                            Rectangle().fill(hovered ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                            Rectangle().fill(agent.tint.opacity(isToday || hovered ? 1 : 0.75)).frame(height: height(mine))
                        }
                        .frame(height: d.tokens > 0 ? height(d.tokens) : 1)
                        .opacity(d.tokens > 0 ? 1 : 0.5)
                        .clipShape(.rect(cornerRadius: 1.5))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: Self.chartHeight)
                    .overlay(alignment: .leading) {
                        if weekStart { Rectangle().fill(.separator).frame(width: 1).offset(x: -1.5) }
                    }
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { hoveredDay = d.id } else if hoveredDay == d.id { hoveredDay = nil }
                    }
                    .overlay(alignment: .bottom) {
                        if label {
                            Text(d.date, format: .dateTime.day())
                                .font(.caption2.weight(isToday ? .semibold : .regular)).monospacedDigit()
                                .foregroundStyle(isToday ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                                .fixedSize()
                                .offset(y: 14)
                        }
                    }
                }
            }
            .opacity(loading ? 0.4 : 1)
            .padding(.bottom, 14)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("최근 30일 토큰 사용량")
            if loading {
                Text("지난 기록을 읽는 중이에요. 처음 한 번은 오래 걸려요.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func tab(_ name: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: name)
                .font(.callout.weight(selected ? .semibold : .regular))
                .padding(.horizontal, 12).padding(.vertical, 5)
                .foregroundStyle(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary))
                .background(selected ? AnyShapeStyle(Color.accentColor.opacity(0.18)) : AnyShapeStyle(.fill.tertiary), in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func detail(_ a: (id: Provider, name: String, symbol: String, tint: Color)) -> some View {
        let b = model.todayDetail[a.id.rawValue] ?? .init()
        let meters: [Meter]? = switch a.id {
        case .claude: model.claudeLimits.map(UsageView.claudeMeters) ?? []
        case .codex: model.codexLimits.map(UsageView.codexMeters) ?? []
        default: nil
        }
        let reset = a.id == .claude ? model.claudeLimits.flatMap(UsageView.claudeReset)
            : a.id == .codex ? model.codexLimits?.primary?.resetDate : nil
        return VStack(alignment: .leading, spacing: 8) {
            ProviderUsageRow(name: a.name, symbol: a.symbol, tint: a.tint, tokens: b.total, cost: b.cost,
                             reset: reset, meters: meters, loading: model.fetchingLimits,
                             emptyText: "한도를 읽지 못했어요. 새로고침해 보세요")
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 3) {
                GridRow {
                    part("입력", b.input)
                    part("출력", b.output)
                }
                GridRow {
                    part("캐시 쓰기", b.cacheWrite)
                    part("캐시 읽기", b.cacheRead)
                }
            }
            .padding(.leading, 36)  // 아이콘(26) + 간격(10) 만큼 들여 이름 줄과 맞춘다
        }
    }

    private func part(_ label: LocalizedStringKey, _ n: Int) -> some View {
        HStack(spacing: 4) {
            Text(label).foregroundStyle(.secondary)
            Text(shortTokens(n)).fontWeight(.medium)
        }
        .font(.caption)
        .monospacedDigit()
    }

    static func costText(_ cost: Double) -> String { String(format: "$%.2f", cost) }
}
