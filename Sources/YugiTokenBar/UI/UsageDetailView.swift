import SwiftUI

/// 팝오버 안 사용량 화면 (상점처럼 요약 위에 겹쳐 그린다).
/// 오늘 합계, 이번 주·이번 달, 최근 30일 막대(에이전트별 색으로 쌓음), 오늘 많이 쓴 순 에이전트별 입력·출력·캐시와 공식 한도.
struct UsageDetailView: View {
    @Environment(AppModel.self) private var model
    /// 마우스를 올린 에이전트 줄. 있으면 막대에 그 몫만 색으로 칠한다
    @State private var hoveredAgent: Provider?
    /// 마우스를 올린 막대의 날짜 (nil 이면 오늘)
    @State private var hoveredDay: String?

    private static let chartDays = 30
    private static let chartHeight = 48.0

    /// byAgent: provider rawValue → 그날 토큰 (막대를 에이전트별로 쌓는다)
    struct Day { let id: String; let date: Date; let tokens: Int; let cost: Double; let byAgent: [String: Int] }

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
        let usage = model.usageByDay
        let (today, week, month) = TodayUsageReader.periods(usage, now: now)
        let days = Self.days(usage, now: now)
        let agents = Self.ranked(usage, today: model.todayDetail)

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
            chart(days, agents: agents)
            VStack(alignment: .leading, spacing: 14) {
                ForEach(agents, id: \.id) { a in
                    detail(a)
                        .background {
                            if hoveredAgent == a.id { RoundedRectangle(cornerRadius: 8).fill(.fill.quaternary).padding(-6) }
                        }
                        .contentShape(Rectangle())
                        .onHover { inside in
                            if inside { hoveredAgent = a.id } else if hoveredAgent == a.id { hoveredAgent = nil }
                        }
                }
            }
        }
    }

    /// 보일 에이전트(Claude·Codex 는 늘, 나머지는 기간 안에 쓴 것만)를 오늘 많이 쓴 순으로. 같으면 기간 합, 그다음 원래 순서
    static func ranked(_ usage: UsageByDay, today: [String: TokenSum]) -> [UsageView.Agent] {
        func period(_ a: UsageView.Agent) -> Int { usage.values.reduce(0) { $0 + ($1[a.id.rawValue]?.total ?? 0) } }
        let shown = UsageView.agents.filter { $0.id == .claude || $0.id == .codex || period($0) > 0 }
        return shown.enumerated().sorted { x, y in
            let a = (today[x.element.id.rawValue]?.total ?? 0, period(x.element), -x.offset)
            let b = (today[y.element.id.rawValue]?.total ?? 0, period(y.element), -y.offset)
            return a > b
        }.map(\.element)
    }

    /// 오늘 포함 최근 count 일 (오래된 날부터)
    static func days(_ usage: UsageByDay, now: Date, count: Int = chartDays) -> [Day] {
        let cal = Calendar.current, fmt = LocalUsageReader.localDayFormatter()
        let today = cal.startOfDay(for: now)
        return (0..<count).reversed().compactMap { back in
            guard let date = cal.date(byAdding: .day, value: -back, to: today) else { return nil }
            let id = fmt.string(from: date), sums = usage[id] ?? [:]
            return Day(id: id, date: date, tokens: sums.values.reduce(0) { $0 + $1.total }, cost: sums.values.reduce(0) { $0 + $1.cost },
                       byAgent: sums.mapValues(\.total))
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

    private func chart(_ days: [Day], agents: [UsageView.Agent]) -> some View {
        let maxTokens = days.map(\.tokens).max() ?? 0
        let shown = days.first { $0.id == hoveredDay } ?? days.last
        let loading = model.pastUsage == nil
        let cal = Calendar.current
        let focus = agents.first { $0.id == hoveredAgent }
        func height(_ n: Int) -> Double { maxTokens > 0 && n > 0 ? max(2, Self.chartHeight * Double(n) / Double(maxTokens)) : 0 }
        return VStack(alignment: .leading, spacing: 4) {
            // 날짜가 있으니 "최근 30일"은 쓰지 않고 한 줄에 둔다
            HStack(spacing: 6) {
                if let shown {
                    // 사용량 문구는 모든 언어에서 영어라 날짜도 영어 표기
                    Text(shown.date, format: .dateTime.month(.defaultDigits).day().weekday(.abbreviated).locale(Locale(identifier: "en_US")))
                        .foregroundStyle(.secondary)
                    Text(shortTokens(focus.map { shown.byAgent[$0.id.rawValue] ?? 0 } ?? shown.tokens)).fontWeight(.semibold)
                    if let focus { Text(verbatim: focus.name).foregroundStyle(focus.tint) }
                    else { Text(Self.costText(shown.cost)).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 4)
                if loading {
                    ProgressView().controlSize(.mini)
                } else {
                    Text("최다").foregroundStyle(.secondary)
                    Text(shortTokens(maxTokens)).fontWeight(.semibold)
                }
            }
            .font(.caption)
            .lineLimit(1)
            .monospacedDigit()
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(days.enumerated()), id: \.element.id) { i, d in
                    let isToday = i == days.count - 1
                    let hovered = d.id == hoveredDay
                    // 주가 바뀌는 날 앞에 가는 선. 날짜는 오늘 라벨과 겹치지 않을 때만
                    let weekStart = i > 0 && cal.component(.weekday, from: d.date) == cal.firstWeekday
                    let label = isToday || (weekStart && i < days.count - 3)
                    let barHeight = d.tokens > 0 ? height(d.tokens) : 1
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        // 평소엔 에이전트별 색을 많이 쓴 순으로 아래부터 쌓고, 에이전트 줄에 마우스를 올리면
                        // 그 몫만 색으로 칠하고 나머지는 회색. 쓴 게 없는 날은 바닥선만
                        ZStack(alignment: .bottom) {
                            Rectangle().fill(.tertiary)
                            if let focus {
                                Rectangle().fill(focus.tint).frame(height: barHeight * share(d, focus))
                            } else {
                                VStack(spacing: 0) {
                                    ForEach(agents.reversed(), id: \.id) { a in
                                        Rectangle().fill(a.tint).frame(height: barHeight * share(d, a))
                                    }
                                }
                            }
                        }
                        .frame(height: barHeight)
                        .opacity(d.tokens == 0 ? 0.5 : isToday || hovered ? 1 : 0.75)
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
                            // 숫자만 (한국어 "12일"처럼 단위가 붙으면 오른쪽 끝에서 잘린다)
                            Text(verbatim: "\(cal.component(.day, from: d.date))")
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

    /// 그날 합 중 그 에이전트 몫 (0...1)
    private func share(_ d: Day, _ a: UsageView.Agent) -> Double {
        d.tokens > 0 ? Double(d.byAgent[a.id.rawValue] ?? 0) / Double(d.tokens) : 0
    }

    private func detail(_ a: UsageView.Agent) -> some View {
        let b = model.todayDetail[a.id.rawValue] ?? .init()
        return VStack(alignment: .leading, spacing: 8) {
            ProviderUsageRow(name: a.name, symbol: a.symbol, tint: a.tint, tokens: b.total, cost: b.cost,
                             reset: model.limitReset(for: a.id), meters: model.meters(for: a.id), loading: model.fetchingLimits,
                             emptyText: "한도를 읽지 못했어요. 새로고침해 보세요")
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 3) {
                // 첫 칸 폭을 고정해 에이전트 줄마다 출력·캐시 읽기 위치가 같다
                GridRow {
                    part("입력", b.input).frame(width: 104, alignment: .leading)
                    part("출력", b.output)
                }
                GridRow {
                    part("캐시 쓰기", b.cacheWrite).frame(width: 104, alignment: .leading)
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
