import SwiftUI

struct ShopView: View {
    @Environment(AppModel.self) private var model
    /// 스크롤 위치(위에서부터 pt). 상점을 닫았다 열거나 앱을 다시 켜도 그 자리로.
    /// @AppStorage 로 두면 스크롤 프레임마다 써서 상점 전체를 다시 그리므로, 멈췄을 때만 UserDefaults 에 직접 쓴다
    private static let scrollKey = "shop.scrollY"
    @State private var position = ScrollPosition()
    /// 복원 전에 들어오는 0 으로 저장값을 덮지 않게
    @State private var restored = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PanelHeader(title: String(localized: "상점"), back: { model.screen = .summary }) {
                Text(coinText(model.game.state.coins))
                    .font(.callout).monospacedDigit().foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(model.db.eras, id: \.name) { era in
                        EraSection(name: era.name, packs: era.packs)
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .scrollPosition($position)
            .panelScrollBottom()
            .onScrollPhaseChange { _, phase, context in
                if restored, phase == .idle {
                    UserDefaults.standard.set(max(0, context.geometry.contentOffset.y), forKey: Self.scrollKey)
                }
            }
            .task {
                // 첫 레이아웃이 끝난 뒤 옮겨야 적용된다
                await Task.yield()
                position.scrollTo(y: UserDefaults.standard.double(forKey: Self.scrollKey))
                restored = true
            }
        }
    }
}

/// 시대별 접고 펴는 팩 묶음. 접힘 상태는 다음 실행에도 기억한다.
private struct EraSection: View {
    @Environment(AppModel.self) private var model
    let name: String
    let packs: Range<Int>
    @AppStorage private var expanded: Bool

    init(name: String, packs: Range<Int>) {
        self.name = name
        self.packs = packs
        _expanded = AppStorage(wrappedValue: true, "shop.era.\(name).expanded")
    }

    var body: some View {
        let game = model.game
        // 시대 범위를 줄이면 부모가 이 섹션을 없애기 전에 몸체가 먼저 다시 그려질 수 있다 → 범위를 지금 DB 에 맞춰 자른다
        let packs = packs.clamped(to: game.db.packs.indices)
        let progress = packs.map { game.progress($0) }
        let owned = progress.reduce(0) { $0 + $1.owned }, total = progress.reduce(0) { $0 + $1.total }
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                    Text(name).font(.headline)
                    Text("\(packs.count)팩").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(owned) / \(total)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded {
                LazyVStack(spacing: 6) {
                    ForEach(packs, id: \.self) { i in
                        ShopRow(index: i)
                    }
                }
                .transition(.opacity)
            }
        }
    }
}

/// 상점 줄: 봉투 · 이름 · 진행 막대와 보유/전체 · 작은 구매 버튼.
private struct ShopRow: View {
    @Environment(AppModel.self) private var model
    let index: Int

    var body: some View {
        let game = model.game
        let pack = game.db.packs[index]
        let p = game.progress(index)
        HStack(spacing: 8) {
            PackImageView(pack: pack)
                .frame(height: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(pack.name).font(.callout).lineLimit(1)
                HStack {
                    TintBar(value: Double(p.owned) / Double(max(p.total, 1)), tint: p.complete ? .green : .accentColor)
                    Text(p.fusionLeft > 0 ? "\(p.owned)/\(p.total) · 융합 \(p.fusionLeft)장 남음" : "\(p.owned)/\(p.total)")
                        .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            Spacer(minLength: 4)
            BuyButton(index: index, cleared: p.cleared).controlSize(.small)
        }
    }
}

/// 팝오버 바로 구매 줄: 팩 이미지 · 이름 · 진행도 · 구매 버튼.
struct PackRow: View {
    @Environment(AppModel.self) private var model
    let index: Int

    var body: some View {
        let game = model.game
        let pack = game.db.packs[index]
        let p = game.progress(index)
        HStack(spacing: 12) {
            PackImageView(pack: pack)
                .frame(height: 50)
                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(pack.name).font(.callout.weight(.medium)).lineLimit(1)
                Text(p.fusionLeft > 0 ? "\(p.owned)/\(p.total) · 융합 \(p.fusionLeft)장 남음" : p.complete ? "완료 · \(p.owned)/\(p.total)" : "\(pack.date.prefix(4)) · \(p.owned)/\(p.total)")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                TintBar(value: Double(p.owned) / Double(max(p.total, 1)), tint: p.complete ? .green : .accentColor)
            }
            Spacer(minLength: 4)
            // 바로 구매 줄은 계속 떠 있고 팩만 바뀌므로, 팩이 바뀌면 "그래도 사기" 상태를 버린다
            BuyButton(index: index, cleared: p.cleared).id(index)
        }
    }
}

/// 1팩 구매 버튼. 가격(코인)을 그대로 보여준다.
/// 더 받을 카드가 없는 팩(`PackProgress.cleared`)은 한 번 막는다: 처음 누르면 "그래도 사기"로 바뀌고, 한 번 더 눌러야 산다.
// ponytail: 메뉴바 패널에선 확인창 대신 버튼을 두 번 누르게 한다(.help 툴팁처럼 시트·알림이 패널에서 불안정)
struct BuyButton: View {
    @Environment(AppModel.self) private var model
    let index: Int
    let cleared: Bool
    @State private var armed = false

    var body: some View {
        let warn = cleared && armed
        Button(warn ? String(localized: "그래도 사기") : coinText(Balance.packPrice)) {
            if cleared && !armed { armed = true } else { armed = false; model.buy(pack: index) }
        }
        .tint(warn ? Palette.badgeLoss : nil)
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.capsule)
        .monospacedDigit()
        .disabled(!model.game.canAffordPack)
    }
}
