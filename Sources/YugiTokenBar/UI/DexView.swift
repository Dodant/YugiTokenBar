import SwiftUI

struct DexView: View {
    @Environment(AppModel.self) private var model
    @State private var scope: DexScope? = .all
    /// 여러 장 선택. 클릭 = 한 장, ⌘클릭 = 토글, ⇧클릭 = 범위 추가, 빈 곳에서 끌기 = 러버밴드.
    @State private var selectedCards: Set<Int> = []
    /// ⇧클릭 범위의 시작점 (마지막으로 클릭한 카드)
    @State private var anchor: Int?
    @State private var marquee: CGRect?
    @State private var marqueeBase: Set<Int> = []
    @State private var frames = FrameStore()
    @State private var listCache = DexListCache()
    @State private var fusableCache = FusableCache()
    @State private var showInspector = true
    /// 융합 소재 링크로 이동 중인 카드: 범위를 바꾸면 onChange 가 선택을 비우므로 그 뒤에 고른다
    @State private var jumpTarget: Int?
    @State private var scrollTarget: Int?
    @State private var fusing: FusionShow?
    /// 0 = 모든 등급, 1~5 = CardInfo.tier
    @State private var tierFilter = 0
    /// "" = 모든 종류, 아니면 CardKind.rawValue 또는 소환법 (CardInfo.matches)
    @State private var kindFilter = ""
    @State private var search = ""
    /// 검색창에 글자를 치는 중엔 ⌘A·Delete 를 검색창에 넘긴다 (안 그러면 툴바 단축키가 가로챈다)
    @FocusState private var searchFocused: Bool
    @State private var showUnowned = true  // 기억하지 않고 창을 열 때마다 켠다
    @AppStorage("dex.sort") private var sort = DexSort.pack
    /// 마지막으로 고른 사이드바 항목과 연 시각. 그날 처음 열면 "전체"로 시작한다
    @AppStorage("dex.scope") private var savedScope = ""
    @AppStorage("dex.scopeDay") private var savedDay = 0.0  // 마지막으로 연 시각(timeIntervalSince1970)

    var body: some View {
        // 카드 목록은 조건(DexQuery)이 바뀔 때만 다시 거르고 정렬한다. 카드 클릭·코인 변화로는 다시 하지 않는다
        let (tiered, entries) = listCache.list(dexQuery, model.game)
        NavigationSplitView {
            DexSidebar(scope: $scope)
                .navigationSplitViewColumnWidth(min: 220, ideal: 250)
        } detail: {
            // .scrollPosition(id:) 는 스크롤 중에도 값을 계속 써서 줄마다 창 전체를 다시 계산하므로, 이동할 때만 쓰는 ScrollViewReader 로
            ScrollView { ScrollViewReader { proxy in
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 12)], spacing: 14) {
                    ForEach(entries) { entry in
                        cell(cid: entry.cid, label: entry.label)
                    }
                }
                .padding(16)
                // 빈 곳: 클릭하면 선택 해제, 끌면 러버밴드 선택
                .background {
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture { selectedCards = [] }
                        .gesture(marqueeGesture)
                }
                .overlay(alignment: .topLeading) {
                    if let marquee {
                        Rectangle().fill(Color.accentColor.opacity(0.12))
                            .overlay(Rectangle().strokeBorder(Color.accentColor.opacity(0.6)))
                            .frame(width: marquee.width, height: marquee.height)
                            .offset(x: marquee.minX, y: marquee.minY)
                            .allowsHitTesting(false)
                    }
                }
                .coordinateSpace(.named("grid"))
                .onChange(of: scrollTarget) {
                    guard let target = scrollTarget else { return }
                    proxy.scrollTo(target, anchor: .center)
                    scrollTarget = nil
                }
            } }
            // ponytail: macOS 26 툴바 유리 그룹 안에선 메뉴 Picker 글자가 안 그려지고 체크박스가 뭉개져서 그리드 위 막대에 둔다
            .safeAreaInset(edge: .top, spacing: 0) { filterBar }
            .overlay {
                if case .deck(let id)? = scope, model.game.deck(id)?.cards.isEmpty ?? true {
                    ContentUnavailableView("덱이 비었어요", systemImage: "rectangle.stack.badge.plus",
                                           description: Text("팩에서 카드를 왼쪽 덱 이름으로 끌어다 놓거나, 카드를 우클릭해 추가하세요"))
                } else if entries.isEmpty, scope == .favorites, model.game.state.favorites.isEmpty {
                    ContentUnavailableView("즐겨찾기한 카드가 없어요", systemImage: "star",
                                           description: Text("카드에 마우스를 올리고 오른쪽 위 ☆를 눌러 보세요"))
                } else if entries.isEmpty, !dexQuery.search.isEmpty, scope != .all {
                    // 팩 안에서 검색해 없을 때: 같은 검색어로 전체에서 다시
                    ContentUnavailableView {
                        Label("'\(search)' 카드가 여기엔 없어요", systemImage: "magnifyingglass")
                    } description: {
                        Text("다른 팩에 있을 수 있어요")
                    } actions: {
                        Button("전체에서 찾기") { scope = .all }
                    }
                } else if entries.isEmpty {
                    ContentUnavailableView(showUnowned ? "조건에 맞는 카드가 없어요" : "보유한 카드가 없어요",
                                           systemImage: "line.3.horizontal.decrease.circle",
                                           description: Text(showUnowned ? "다른 팩이나 종류·등급을 골라 보세요" : "미보유 카드 포함을 켜면 전부 보여요"))
                }
            }
            .onChange(of: scope) {
                selectedCards = jumpTarget.map { [$0] } ?? []; anchor = jumpTarget; jumpTarget = nil
                if let scope { savedScope = scope.key }
            }
            .onAppear { restoreScope() }
            // 설정에서 시대 범위를 줄여 보던 팩이 사라지면 "전체"로
            .onChange(of: model.db.packs.count) { if case .pack(let i)? = scope, i >= model.db.packs.count { scope = .all } }
            .navigationTitle(title)
            .navigationSubtitle(subtitle(tiered))
            .searchable(text: $search, placement: .toolbar, prompt: "카드 이름")
            .searchFocused($searchFocused)
            .inspector(isPresented: $showInspector) {
                detail.inspectorColumnWidth(min: 240, ideal: 260)
            }
            .toolbar {
                SellDuplicatesButton()
                // 러버밴드는 보이는 셀만 잡으니, 필터된 목록 전체는 이걸로
                Button {
                    selectedCards = Set(entries.map(\.cid))
                    showInspector = true
                } label: {
                    Label("전체 선택", systemImage: "checklist")
                }
                .keyboardShortcut(searchFocused ? nil : KeyboardShortcut("a"))
                .help("지금 보이는 카드 모두 선택 (⌘A)")
                .disabled(entries.isEmpty)
                if let deckID {
                    let picked = selectedCards.filter { model.game.deck(deckID)?.cards[$0] != nil }
                    Button {
                        removeFromDeck(deckID, picked)
                    } label: {
                        Label("덱에서 빼기", systemImage: "minus.circle")
                    }
                    .keyboardShortcut(searchFocused ? nil : KeyboardShortcut(.delete, modifiers: []))
                    .help("선택한 카드를 덱에서 1장씩 빼기 (Delete)")
                    .disabled(picked.isEmpty)
                }
                Button { showInspector.toggle() } label: { Label("정보", systemImage: "sidebar.trailing") }
            }
        }
        .overlay {
            if let fusing {
                FusionAnimationView(db: model.db, show: fusing) { self.fusing = nil }
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: fusing)
    }

    private var filterBar: some View {
        HStack(spacing: 14) {
            Picker("종류", selection: $kindFilter) {
                Text("모든 종류").tag("")
                Divider()
                ForEach(CardKind.allCases, id: \.self) { Text($0.rawValue).tag($0.rawValue) }
                Divider()
                ForEach(CardInfo.summons, id: \.self) { Text($0).tag($0) }
            }
            .fixedSize()
            Picker("등급", selection: $tierFilter) {
                Text("모든 등급").tag(0)
                Divider()
                Text("N 노멀").tag(1)
                Text("R 레어").tag(2)
                Text("SR 슈퍼").tag(3)
                Text("UR 울트라").tag(4)
                Text("SE 시크릿").tag(5)
            }
            .fixedSize()
            Picker("정렬", selection: $sort) {
                ForEach(DexSort.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .fixedSize()
            Spacer()
            Toggle("미보유 카드 포함", isOn: $showUnowned)
                .toggleStyle(.checkbox)
                .help("끄면 가진 카드만 보여요")
        }
        .pickerStyle(.menu)
        .controlSize(.small)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var title: String {
        switch scope {
        case .favorites?: "즐겨찾기"
        case .pack(let i)? where model.db.packs.indices.contains(i): model.db.packs[i].name
        case .deck(let id)?: model.game.deck(id)?.name ?? "덱"
        default: "전체"
        }
    }

    private func subtitle(_ all: [DexEntry]) -> String {
        if case .deck(let id)? = scope, let deck = model.game.deck(id) {
            let p = model.game.deckProgress(deck)
            return "\(p.owned) / \(p.total)장 보유 · 메인 덱 \(Balance.deckSize.lowerBound)~\(Balance.deckSize.upperBound)장"
        }
        let owned = all.filter { model.game.copies($0.cid) > 0 }.count
        return "\(owned) / \(all.count)장 보유"
    }

    /// 화면에 보일 카드 (body 밖 동작용. 조건이 같으면 캐시를 그대로 쓴다)
    private var entries: [DexEntry] { listCache.list(dexQuery, model.game).visible }

    /// 지금 그리드 조건. 보유·즐겨찾기·덱은 결과에 영향을 줄 때만 넣어서, 상관없는 변화(코인 등)로는 다시 계산하지 않는다
    private var dexQuery: DexQuery {
        let state = model.game.state
        return DexQuery(
            scope: scope, tier: tierFilter, kind: kindFilter,
            search: search.replacingOccurrences(of: " ", with: ""),
            showUnowned: showUnowned, sort: sort, era: state.eraLimit,
            owned: !showUnowned || sort == .copies ? state.owned : nil,
            favorites: scope == .favorites ? state.favorites : nil,
            deck: deckID.map { id in Set(model.game.deck(id)?.cards.keys.map { $0 } ?? []) })
    }

    /// 그날 처음 열면 "전체", 아니면 마지막 항목(범위 밖 팩·지운 덱이면 "전체")
    private func restoreScope() {
        let sameDay = Calendar.current.isDateInToday(Date(timeIntervalSince1970: savedDay))
        let restored: DexScope? = sameDay ? DexScope(key: savedScope) : nil
        savedDay = Date().timeIntervalSince1970
        switch restored {
        case .pack(let i)? where model.db.packs.indices.contains(i): scope = restored
        case .deck(let id)? where model.game.deck(id) != nil: scope = restored
        case .favorites?: scope = restored
        default: scope = .all
        }
    }

    /// 보고 있는 덱 (덱 화면이 아니면 nil)
    private var deckID: UUID? { if case .deck(let id)? = scope { id } else { nil } }

    /// 융합 소재 링크: 필터·검색을 풀고, 지금 범위에 없으면 "전체"로 옮겨 그 카드를 고르고 보이게 스크롤한다
    private func jump(to cid: Int) {
        kindFilter = ""; tierFilter = 0; search = ""; showUnowned = true
        if entries.contains(where: { $0.cid == cid }) {
            selectedCards = [cid]; anchor = cid
        } else {
            jumpTarget = cid; scope = .all
        }
        scrollTarget = entries.first { $0.cid == cid }?.number
    }

    /// 끌기·우클릭이 적용되는 카드들: 선택된 카드면 선택 전체, 아니면 그 카드만.
    private func targets(_ cid: Int) -> Set<Int> { selectedCards.contains(cid) ? selectedCards : [cid] }

    private func cell(cid: Int, label: String) -> some View {
        let game = model.game
        // 덱 화면에선 덱에 넣은 장 수를 보여주고, 보유가 그보다 적으면 미보유처럼 흐리게(더 모아야 할 카드)
        let inDeck = deckID.flatMap { game.deck($0)?.cards[cid] }
        let n = inDeck ?? game.copies(cid)
        let owned = inDeck.map { game.copies(cid) >= $0 } ?? (n > 0)
        let selected = selectedCards.contains(cid)
        return Hovering { hovered in VStack(spacing: 4) {
            CardImageView(db: model.db, cid: cid, owned: owned)
                .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.accentColor, lineWidth: selected ? 3 : 0))
                .overlay(alignment: .topTrailing) { star(cid, hovered: hovered) }
                .overlay(alignment: .topLeading) { if let deckID, hovered { minus(deckID, cid) } }
                .overlay(alignment: .bottomLeading) { RarityPill(label: label, owned: owned).padding(4) }
            HStack(spacing: 4) {
                Text(model.db.cards[cid]?.name ?? "")
                    .lineLimit(1).truncationMode(.tail)
                    .foregroundStyle(owned ? .primary : .secondary)
                Spacer(minLength: 0)
                if n > 1 || inDeck != nil { Text("×\(n)").fontWeight(.semibold).monospacedDigit() }
            }
            .font(.caption2)
        }
        .contentShape(Rectangle()) }
        .help(model.db.cards[cid]?.name ?? "")
        .onTapGesture { select(cid) }
        // VoiceOver: 셀 하나를 카드 한 장으로 읽고, 마우스를 올려야 보이는 ☆·− 는 동작으로 둔다
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cellLabel(cid, label: label, inDeck: inDeck))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { select(cid) }
        .accessibilityActions {
            Button(game.state.favorites.contains(cid) ? "즐겨찾기 해제" : "즐겨찾기") { model.toggleFavorite(cid) }
            if let deckID { Button("덱에서 1장 빼기") { model.removeFromDeck(deckID, [cid]) } }
        }
        // 사이드바 덱 줄에 끌어다 놓는다. 페이로드는 cid 를 쉼표로 이은 문자열 (선택된 카드를 끌면 선택 전체).
        .draggable(targets(cid).sorted().map(String.init).joined(separator: ",")) {
            DragPreview(db: model.db, cids: targets(cid).sorted())
        }
        .contextMenu { deckMenu(targets(cid), inDeck: deckID) }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("grid")) } action: { frames.map[cid] = $0 }
        .onDisappear { frames.map[cid] = nil }
    }

    /// "푸른 눈의 백룡, UR, 보유 2장" (덱 화면이면 "덱 3장, 보유 2장")
    private func cellLabel(_ cid: Int, label: String, inDeck: Int?) -> String {
        let n = model.game.copies(cid)
        let status = inDeck.map { "덱 \($0)장, 보유 \(n)장" } ?? (n > 0 ? "보유 \(n)장" : "미보유")
        return "\(model.db.cards[cid]?.name ?? ""), \(label), \(status)"
    }

    /// 클릭 = 그 카드만, ⌘클릭 = 토글, ⇧클릭 = 마지막 클릭부터 범위 추가. (Ctrl클릭은 macOS 우클릭이라 안 쓴다)
    private func select(_ cid: Int) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if selectedCards.remove(cid) == nil { selectedCards.insert(cid) }
        } else if flags.contains(.shift), let anchor,
                  let a = entries.firstIndex(where: { $0.cid == anchor }),
                  let b = entries.firstIndex(where: { $0.cid == cid }) {
            selectedCards.formUnion(entries[min(a, b)...max(a, b)].map(\.cid))
            return  // 앵커는 그대로
        } else {
            selectedCards = [cid]
        }
        anchor = cid
        showInspector = true
    }

    /// 빈 곳에서 끌어 사각형에 걸리는 카드를 고른다. ⌘·⇧를 누르고 있으면 기존 선택에 더한다.
    private var marqueeGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("grid"))
            .onChanged { v in
                if marquee == nil {
                    marqueeBase = NSEvent.modifierFlags.intersection([.command, .shift]).isEmpty ? [] : selectedCards
                }
                let rect = CGRect(x: min(v.startLocation.x, v.location.x), y: min(v.startLocation.y, v.location.y),
                                  width: abs(v.translation.width), height: abs(v.translation.height))
                marquee = rect
                // ponytail: 화면에 보이는 셀만 걸린다(LazyVGrid 는 화면 밖 셀을 만들지 않음). 더 고르려면 ⌘/⇧ 러버밴드로 더한다
                selectedCards = marqueeBase.union(frames.map.filter { $0.value.intersects(rect) }.keys)
            }
            .onEnded { _ in marquee = nil }
    }

    /// 덱 화면의 빼기 단추: 마우스를 올렸을 때만.
    private func minus(_ deck: UUID, _ cid: Int) -> some View {
        Button { model.removeFromDeck(deck, [cid]) } label: {
            Image(systemName: "minus")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(.black.opacity(0.45), in: Circle())
        }
        .buttonStyle(.plain)
        .padding(3)
        .help("덱에서 1장 빼기")
    }

    /// 우클릭·선택 메뉴: 덱 화면이면 빼기, 아니면 덱에 넣기(미보유도 가능). 여러 장이면 장 수를 붙인다.
    @ViewBuilder private func deckMenu(_ cids: Set<Int>, inDeck deck: UUID?) -> some View {
        let many = cids.count > 1 ? " (\(cids.count)장)" : ""
        if let deck {
            Button("덱에서 1장씩 빼기\(many)") {
                removeFromDeck(deck, cids)
            }
        } else {
            let decks = model.game.state.decks
            if decks.isEmpty {
                Button("새 덱에 추가\(many)") { model.addToDeckOrBeep(model.addDeck().id, cids) }
            } else {
                Menu("덱에 추가\(many)") {
                    ForEach(decks) { d in
                        let p = model.game.deckProgress(d)
                        Button("\(d.name) · \(p.owned)/\(p.total)") { model.addToDeckOrBeep(d.id, cids) }
                    }
                }
            }
        }
    }

    /// 덱에서 1장씩 빼고, 0장이 된 카드는 선택에서도 뺀다.
    private func removeFromDeck(_ deck: UUID, _ cids: Set<Int>) {
        model.removeFromDeck(deck, cids)
        selectedCards = selectedCards.filter { model.game.deck(deck)?.cards[$0] != nil }
    }

    /// 즐겨찾기 별: 체크된 카드는 항상, 아니면 마우스를 올렸을 때만.
    @ViewBuilder private func star(_ cid: Int, hovered: Bool) -> some View {
        let on = model.game.state.favorites.contains(cid)
        if on || hovered {
            Button { model.toggleFavorite(cid) } label: {
                Image(systemName: on ? "star.fill" : "star")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(on ? .yellow : .white)
                    .frame(width: 22, height: 22)
                    .background(.black.opacity(0.45), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(3)
            .help(on ? "즐겨찾기 해제" : "즐겨찾기")
        }
    }

    /// 오른쪽 패널: 융합할 수 있는 카드가 있을 때만 맨 위에 "융합 가능" 목록, 그 아래 선택한 카드 정보
    private var detail: some View {
        VStack(spacing: 0) {
            FusableSection(selected: selectedCards, cache: fusableCache, jump: jump)
            cardDetail.frame(maxHeight: .infinity)
        }
    }

    @ViewBuilder private var cardDetail: some View {
        if selectedCards.count > 1 {
            ContentUnavailableView {
                Label("\(selectedCards.count)장 선택됨", systemImage: "rectangle.on.rectangle")
            } description: {
                Text("왼쪽 덱 이름으로 끌어다 놓거나 아래에서 덱을 고르세요")
            } actions: {
                deckMenu(selectedCards, inDeck: deckID)
            }
        } else if let cid = selectedCards.first, let card = model.db.cards[cid] {
            CardDetailView(cid: cid, card: card, jump: jump) { fusing = $0 }
        } else {
            ContentUnavailableView("카드를 선택하세요", systemImage: "rectangle.portrait.on.rectangle.portrait",
                                   description: Text("카드를 누르면 자세한 정보가 여기 나와요"))
        }
    }
}

/// 끌 때 보이는 미리보기: 첫 카드 + 여러 장이면 장 수 배지.
private struct DragPreview: View {
    let db: CardDB
    let cids: [Int]

    var body: some View {
        CardImageView(db: db, cid: cids.first ?? 0)
            .frame(width: 60)
            .overlay(alignment: .topTrailing) {
                if cids.count > 1 {
                    Text("\(cids.count)")
                        .font(.caption.weight(.bold)).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.red, in: Capsule())
                        .offset(x: 6, y: -6)
                }
            }
    }
}

/// 마우스 올림 상태를 셀 안에 둔다. DexView 의 @State 로 두면 스크롤 중 셀이 커서 밑을 지날 때마다
/// 창 전체(카드 목록 필터·정렬)를 다시 계산해서 버벅인다.
private struct Hovering<Content: View>: View {
    @ViewBuilder let content: (Bool) -> Content
    @State private var hovered = false

    var body: some View { content(hovered).onHover { hovered = $0 } }
}

/// 화면에 보이는 셀의 프레임 (러버밴드 선택용). 클래스라 갱신해도 뷰를 다시 그리지 않는다.
private final class FrameStore {
    var map: [Int: CGRect] = [:]
}

/// 툴바 [중복 모두 팔기]. 따로 둬서 카드를 클릭해도 중복 수를 다시 세지 않는다.
private struct SellDuplicatesButton: View {
    @Environment(AppModel.self) private var model
    @State private var confirm = false

    var body: some View {
        let dup = model.game.duplicatesValue
        Button { confirm = true } label: {
            Label("중복 모두 팔기", systemImage: "c.circle").labelStyle(.titleAndIcon)
        }
        .help("카드마다 1장\(model.game.state.fusionOnly ? ", 융합 소재는 필요한 장 수" : "")만 남기고 모두 팔아요 (\(dup.count)장 · +\(coinText(dup.coins)))")
        .disabled(dup.count == 0)
        .confirmationDialog("중복 \(dup.count)장을 팔까요?", isPresented: $confirm) {
            Button("+\(coinText(dup.coins))에 판매") { model.sellDuplicates() }
        } message: {
            Text(model.game.state.fusionOnly ? "카드마다 1장씩, 융합 소재는 필요한 장 수만큼 남아서 컬렉션은 그대로예요." : "카드마다 1장씩은 남아서 컬렉션은 그대로예요.")
        }
    }
}
