import SwiftUI

/// 팝오버 안 사용량 화면 (상점처럼 요약 위에 겹쳐 그린다).
/// 오늘 합계, 이번 주·이번 달, 쓴 날 14개 막대(에이전트별 색으로 쌓고 안 쓴 날은 빨간 선으로 접음), 오늘 많이 쓴 순 에이전트별 입력·출력·캐시와 공식 한도.
struct UsageDetailView: View {
    @Environment(AppModel.self) private var model
    /// 마우스를 올린 에이전트 줄. 있으면 막대에 그 몫만 색으로 칠한다
    @State private var hoveredAgent: Provider?
    /// 마우스를 올린 막대의 날짜 (nil 이면 오늘)
    @State private var hoveredDay: String?

    private static let chartDays = 14
    private static let chartHeight = 48.0
    /// 막대 위 그날 얻은 카드 수 자리
    private static let cardLabelHeight = 11.0

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
                // 에이전트 줄 배경(-6)이 잘리지 않게 안쪽 여백을 두고, 그만큼 스크롤 영역을 넓혀 내용 폭은 그대로
                // (넓히기는 panelScrollBottom 의 마스크 바깥에서 해야 마스크도 같이 넓어진다)
                content.padding(.horizontal, 8)
            }
            .scrollIndicators(.never)
            .frame(maxHeight: .infinity)
            .panelScrollBottom()
            .padding(.horizontal, -6)
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
        // 읽는 동안은 지난 날이 모두 0이라 접지 않고 최근 14일을 그대로 보인다
        let days = model.pastUsage == nil ? Self.days(usage, now: now)
            : Self.activeDays(Self.days(usage, now: now, count: TodayUsageReader.historyDays + 1))
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
                            if hoveredAgent == a.id { RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.fill.quaternary).padding(-6) }
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

    /// 쓴 날(오늘은 늘 셈)이 count 개가 될 때까지 과거로 넓힌다. 기록이 모자라면 맨 처음 쓴 날부터
    static func activeDays(_ all: [Day], count: Int = chartDays) -> [Day] {
        var n = 0
        let start = all.indices.reversed().first { i in
            if i == all.count - 1 || all[i].tokens > 0 { n += 1 }
            return n == count
        } ?? all.firstIndex { $0.tokens > 0 } ?? all.count - 1
        return Array(all[start...])
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
        let cardsByDay = model.game.state.cardsByDay
        func height(_ n: Int) -> Double { maxTokens > 0 && n > 0 ? max(2, Self.chartHeight * Double(n) / Double(maxTokens)) : 0 }
        return VStack(alignment: .leading, spacing: 4) {
            // 날짜가 있으니 "최근 14일"은 쓰지 않고 한 줄에 둔다
            HStack(spacing: 6) {
                if let shown {
                    // 사용량 문구는 모든 언어에서 영어라 날짜도 영어 표기
                    Text(shown.date, format: .dateTime.month(.defaultDigits).day().weekday(.abbreviated).locale(Locale(identifier: "en_US")))
                        .foregroundStyle(.secondary)
                    Text(shortTokens(focus.map { shown.byAgent[$0.id.rawValue] ?? 0 } ?? shown.tokens)).fontWeight(.semibold)
                    if let focus { Text(verbatim: focus.name).foregroundStyle(focus.tint) }
                    else { Text(Self.costText(shown.cost)).foregroundStyle(.secondary) }
                    if let cards = cardsByDay[shown.id] {
                        // 문구 없이 카드 모양과 장 수만 (모든 언어 같은 표기)
                        Label { Text(verbatim: "\(cards)") } icon: { Image(systemName: "rectangle.portrait.on.rectangle.portrait") }
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(String(localized: "얻은 카드 \(cards)장"))
                    }
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
            // 쓴 게 없는 날(오늘 빼고)이 이어지면 빨간 선 하나로 줄인다. 읽는 동안은 줄이지 않는다
            let idle = { (i: Int) in !loading && i < days.count - 1 && days[i].tokens == 0 }
            let slots = days.indices.filter { !idle($0) || $0 == 0 || !idle($0 - 1) }
            // 날짜를 다는 날: 오늘, 주 첫날, 빨간 선 다음 날. 앞 라벨과 막대 둘 이상 떨어지고 오늘 앞 사흘이 아닐 때만
            let labeled: Set<Int> = {
                var out: Set<Int> = [days.count - 1], last = -3
                for (k, i) in slots.enumerated() where !idle(i) && i < days.count - 3 {
                    let weekStart = cal.component(.weekday, from: days[i].date) == cal.firstWeekday
                    guard (weekStart || (i > 0 && idle(i - 1))) && k - last >= 3 else { continue }
                    out.insert(i); last = k
                }
                return out
            }()
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(slots, id: \.self) { i in
                    let d = days[i]
                    if idle(i) {
                        Rectangle().fill(.red).frame(width: 2, height: Self.chartHeight)
                    } else {
                        let isToday = i == days.count - 1
                        let hovered = d.id == hoveredDay
                        // 주가 바뀌는 날 앞에 가는 선(빨간 선 바로 뒤는 빼고)
                        let weekStart = i > 0 && !idle(i - 1) && cal.component(.weekday, from: d.date) == cal.firstWeekday
                        let label = labeled.contains(i)
                        let barHeight = d.tokens > 0 ? height(d.tokens) : 1
                        VStack(spacing: 1) {
                            Spacer(minLength: 0)
                            if let cards = cardsByDay[d.id] {
                                Text(verbatim: "\(cards)").font(.system(size: 8)).monospacedDigit()
                                    .foregroundStyle(.secondary).lineLimit(1).fixedSize()
                            }
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
                        .frame(height: Self.chartHeight + Self.cardLabelHeight)
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
            }
            .opacity(loading ? 0.4 : 1)
            .padding(.bottom, 14)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("최근 쓴 14일 토큰 사용량")
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
