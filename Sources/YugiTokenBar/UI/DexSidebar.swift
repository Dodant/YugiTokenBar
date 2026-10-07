import SwiftUI

/// 컬렉션 사이드바. 따로 둬서 카드를 클릭(선택)해도 팩·등급 통계를 다시 세지 않는다.
struct DexSidebar: View {
    @Environment(AppModel.self) private var model
    @Binding var scope: DexScope?
    @State private var renaming: Deck?
    @State private var newName = ""
    @State private var deleting: Deck?

    var body: some View {
        let game = model.game
        List(selection: $scope) {
            Label {
                HStack {
                    Text("전체")
                    Spacer()
                    Text("\(game.ownedDistinct) / \(game.db.allCIDs.count)").foregroundStyle(.secondary).monospacedDigit()
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
            ForEach(game.db.eras, id: \.name) { era in
                DexEraSection(name: era.name, packs: era.packs) { i in packItem(game, i) }
            }
            deckSection
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) { tierStats(game) }
        .alert("덱 이름", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("이름", text: $newName)
            Button("저장") { if let deck = renaming { model.renameDeck(deck.id, to: newName) } }
            Button("취소", role: .cancel) {}
        }
        .confirmationDialog("'\(deleting?.name ?? "")' 덱을 지울까요?",
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
            PackImageView(pack: pack)
                .frame(height: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(pack.name).lineLimit(1)
                HStack {
                    ProgressView(value: Double(p.owned), total: Double(p.total)).controlSize(.mini)
                    Text("\(p.owned)/\(p.total)").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
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
                        Button("이름 바꾸기") { newName = deck.name; renaming = deck }
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

    /// 사이드바 아래: 등급마다 보유/전체 종류 수와 모은 비율
    private func tierStats(_ game: Game) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 5) {
            ForEach(Array(game.tierProgress.enumerated()), id: \.offset) { i, p in
                let label = CardInfo.rarities[i]
                let ratio = p.total > 0 ? Double(p.owned) / Double(p.total) : 0
                GridRow {
                    RarityPill(label: label).gridColumnAlignment(.center)
                    ProgressView(value: ratio).tint(Rarity.color(label: label)).controlSize(.small)
                    Text("\(p.owned) / \(p.total)").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                    Text(ratio, format: .percent.precision(.fractionLength(1))).gridColumnAlignment(.trailing)
                }
            }
        }
        .font(.caption)
        .monospacedDigit()
        .padding(12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

/// 사이드바의 시대(DM/GX) 묶음. 헤더를 눌러 접고 펴며, 접힘 상태는 다음 실행에도 기억한다.
private struct DexEraSection<Item: View>: View {
    @Environment(AppModel.self) private var model
    let name: String
    let packs: Range<Int>
    let item: (Int) -> Item
    @AppStorage private var expanded: Bool

    init(name: String, packs: Range<Int>, @ViewBuilder item: @escaping (Int) -> Item) {
        self.name = name
        self.packs = packs
        self.item = item
        _expanded = AppStorage(wrappedValue: true, "dex.era.\(name).expanded")
    }

    var body: some View {
        let game = model.game
        // 시대 범위를 줄이면 부모가 이 섹션을 없애기 전에 몸체가 먼저 다시 그려질 수 있다 → 범위를 지금 DB 에 맞춰 자른다
        let packs = packs.clamped(to: game.db.packs.indices)
        let progress = packs.map { game.progress($0) }
        let owned = progress.reduce(0) { $0 + $1.owned }, total = progress.reduce(0) { $0 + $1.total }
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
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                    Text("\(name) · \(packs.count)팩")
                    Spacer()
                    Text("\(owned) / \(total)").monospacedDigit()
                }
                .padding(.leading, 3).padding(.trailing, 6)  // 사이드바 헤더는 행보다 안쪽 여백이 적어서 전체·즐겨찾기 행의 아이콘·숫자 끝에 맞춘다
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
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
                Text(deck.name).lineLimit(1)
                HStack {
                    ProgressView(value: Double(p.owned), total: Double(max(p.total, 1))).controlSize(.mini)
                        .tint(p.total > 0 && p.owned == p.total ? .green : .accentColor)
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
