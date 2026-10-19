#if os(macOS)
import SwiftUI

/// 컬렉션 사이드바. 따로 둬서 카드를 클릭(선택)해도 팩·등급 통계를 다시 세지 않는다.
struct DexSidebar: View {
    @Environment(\.workMode) private var workMode
    @Environment(AppModel.self) private var model
    @Binding var scope: DexScope?
    @State private var renaming: Deck?
    @State private var newName = ""
    @State private var deleting: Deck?
    @State private var memo = GameMemo(SidebarStats.init)
    @AppStorage("dex.progressExpanded") private var progressExpanded = true
    /// 펼친 등급 표 높이. 접고 펼 때 이 높이와 0 사이를 움직인다
    @State private var progressHeight: CGFloat = 0
    @Environment(\.lessMotion) private var lessMotion

    var body: some View {
        let game = model.game
        let stats = memo(game)
        List(selection: $scope) {
            Label {
                HStack {
                    Text("전체")
                    Spacer()
                    Text("\(stats.ownedDistinct) / \(game.db.allCIDs.count)").foregroundStyle(.secondary).monospacedDigit()
                }
            } icon: {
                Image(systemName: "square.grid.2x2")
            }
            .tag(DexScope.all)
            Label {
                HStack {
                    Text("즐겨찾기")
                    Spacer()
                    Text("\(game.favoritesInRange)").foregroundStyle(.secondary).monospacedDigit()
                }
            } icon: {
                Image(systemName: "star.fill").foregroundStyle(.yellow)
            }
            .tag(DexScope.favorites)
            Label("최근 획득", systemImage: "clock").tag(DexScope.recent)
            ForEach(game.db.eras, id: \.name) { era in
                DexEraSection(name: era.name, packs: era.packs, progress: stats.eras[era.name] ?? (0, 0)) { i in packItem(game, i) }
            }
            deckSection
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) { tierStats(stats.tiers, overframe: stats.overframe) }
        .alert("덱 이름", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("이름", text: $newName)
            Button("저장") { if let deck = renaming { model.renameDeck(deck.id, to: newName) } }
            Button("취소", role: .cancel) {}
        }
        .confirmationDialog("'\(deleting?.title ?? "")' 덱을 지울까요?",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("삭제", role: .destructive) {
                guard let deck = deleting else { return }
                if scope == .deck(deck.id) { scope = .all }
                model.deleteDeck(deck.id)
            }
        } message: {
            Text("카드는 컬렉션에 그대로 있어요.")
        }
    }

    private func packItem(_ game: Game, _ i: Int) -> some View {
        let pack = game.db.packs[i]
        let p = game.progress(i)
        return HStack(spacing: 8) {
            if !workMode {  // 업무 모드면 봉투 자리 없이
                PackImageView(pack: pack)
                    .frame(height: 36)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(pack.name).lineLimit(1)
                HStack {
                    ProgressBar(owned: p.owned, total: p.total)
                    ProgressCount(owned: p.owned, total: p.total)
                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                }
            }
        }
        .padding(.vertical, 2)
    }

    /// 사이드바 "덱" 묶음: + 로 새 덱, 줄에 카드를 끌어다 놓으면 추가, 우클릭으로 이름 바꾸기·삭제.
    private var deckSection: some View {
        Section {
            ForEach(model.game.state.decks) { deck in
                DeckRow(deck: deck)
                    .tag(DexScope.deck(deck.id))
                    .contextMenu {
                        Button("이름 바꾸기") { newName = deck.title; renaming = deck }
                        Button("삭제", role: .destructive) { deleting = deck }
                    }
            }
        } header: {
            HStack {
                Text("덱")
                Spacer()
                Button("새 덱", systemImage: "plus") { scope = .deck(model.addDeck().id) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .help("새 덱")
            }
            .padding(.leading, 3).padding(.trailing, 6)  // 시대 헤더와 같은 여백
        }
    }

    /// 사이드바 아래: 등급마다 보유/전체 종류 수와 모은 비율, 맨 아래 ✦ 오버프레임 해금 수. 머리줄을 눌러 접고 펴며 기억한다.
    private func tierStats(_ tiers: [(owned: Int, total: Int)], overframe: (owned: Int, total: Int)) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(lessMotion ? nil : .smooth(duration: 0.3)) { progressExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    DisclosureChevron(expanded: progressExpanded)
                    Text("진행도")
                    Spacer()
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // 넣고 빼지 않고 늘 그려 둔 표의 높이를 줄여(위쪽 고정) 띠가 부드럽게 접히고 펴진다
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 5) {
                ForEach(Array(tiers.enumerated()), id: \.offset) { i, p in
                    let label = CardInfo.rarities[i]
                    statRow(RarityPill(label: label), p, tint: Rarity.color(label: label))
                }
                if overframe.total > 0 {
                    statRow(OverframeBadge(unlocked: true, copies: 0, hint: false).help("오버프레임 그림 해금"), overframe, tint: Rarity.overframe)
                }
            }
            .padding(.top, 8)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { progressHeight = $0 }
            .frame(height: progressExpanded ? progressHeight : 0, alignment: .top)
            .clipped()
            .opacity(progressExpanded ? 1 : 0)
            .accessibilityHidden(!progressExpanded)
        }
        .font(.caption)
        .monospacedDigit()
        .padding(12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func statRow(_ pill: some View, _ p: (owned: Int, total: Int), tint: Color) -> some View {
        let ratio = p.total > 0 ? Double(p.owned) / Double(p.total) : 0
        return GridRow {
            pill.gridColumnAlignment(.center)
            TintBar(value: ratio, tint: tint, height: 5)
            Text("\(p.owned) / \(p.total)").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            Text(ratio, format: .percent.precision(.fractionLength(1))).gridColumnAlignment(.trailing)
        }
    }
}

/// 사이드바의 시대(DM/GX) 묶음. 헤더를 눌러 접고 펴며, 접힘 상태는 다음 실행에도 기억한다.
private struct DexEraSection<Item: View>: View {
    @Environment(AppModel.self) private var model
    let name: String
    let packs: Range<Int>
    /// 이 시대 팩들의 보유 / 전체 (부모가 `SidebarStats` 에서 넘긴다)
    let progress: (owned: Int, total: Int)
    let item: (Int) -> Item
    @AppStorage private var expanded: Bool

    init(name: String, packs: Range<Int>, progress: (owned: Int, total: Int), @ViewBuilder item: @escaping (Int) -> Item) {
        self.name = name
        self.packs = packs
        self.progress = progress
        self.item = item
        _expanded = AppStorage(wrappedValue: true, "dex.era.\(name).expanded")
    }

    var body: some View {
        let game = model.game
        // 시대 범위를 줄이면 부모가 이 섹션을 없애기 전에 몸체가 먼저 다시 그려질 수 있다 → 범위를 지금 DB 에 맞춰 자른다
        let packs = packs.clamped(to: game.db.packs.indices)
        // ponytail: 기본 사이드바 꺾쇠는 마우스를 올려야 보여서, 상점처럼 항상 보이는 꺾쇠를 직접 그린다
        Section {
            if expanded {
                ForEach(packs, id: \.self) { i in item(i).tag(DexScope.pack(i)) }
            }
        } header: {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    DisclosureChevron(expanded: expanded)
                    Text("\(name) · \(packs.count)팩")
                    Spacer()
                    Text("\(progress.owned) / \(progress.total)").monospacedDigit()
                }
                .padding(.leading, 3).padding(.trailing, 6)  // 사이드바 헤더는 행보다 안쪽 여백이 적어서 전체·즐겨찾기 행의 아이콘·숫자 끝에 맞춘다
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

/// 사이드바가 game 에서 세는 값: 전체 보유 종류 수, 등급별 보유/전체, 오버프레임 해금/전체, 시대별 보유/전체.
/// 카드 선택·코인 적립으로 game 이 바뀌어도 보유·설정·시대가 같으면 8천 장을 다시 훑지 않는다 (`GameMemo`).
/// 팩 줄의 진행은 List 가 보이는 줄만 만들어 그대로 `Game.progress(_:)` 를 쓴다.
private struct SidebarStats {
    let ownedDistinct: Int
    let tiers: [(owned: Int, total: Int)]
    let overframe: (owned: Int, total: Int)
    let eras: [String: (owned: Int, total: Int)]

    init(_ game: Game) {
        ownedDistinct = game.ownedDistinct
        tiers = game.tierProgress
        overframe = game.overframeProgress
        eras = Dictionary(uniqueKeysWithValues: game.db.eras.map { ($0.name, game.progress(packs: $0.packs)) })
    }
}

/// 사이드바 덱 한 줄: 팩 줄처럼 이름·진행 바·보유/덱 장 수. 카드를 끌어다 놓으면 그 덱에 1장 넣는다(못 넣으면 비프).
private struct DeckRow: View {
    @Environment(AppModel.self) private var model
    let deck: Deck
    @State private var targeted = false

    var body: some View {
        let p = model.game.deckProgress(deck)
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(deck.title).lineLimit(1)
                HStack {
                    ProgressBar(owned: p.owned, total: p.total)
                    Text("\(p.owned)/\(p.total)").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .padding(.vertical, 2)
        } icon: {
            Image(systemName: "rectangle.stack")
        }
        .listRowBackground(targeted ? Color.accentColor.opacity(0.25) : nil)
        .dropDestination(for: String.self) { items, _ in
            let added = model.addToDeckOrBeep(deck.id, items.flatMap { $0.split(separator: ",") }.compactMap { Int($0) })
            return added > 0
        } isTargeted: { targeted = $0 }
    }
}
#endif
