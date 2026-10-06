import SwiftUI

struct DexView: View {
    @EnvironmentObject var model: AppModel
    @MainActor private static var nameRank: [Int: Int] = [:]
    @State private var scope: DexScope? = .all
    @State private var renaming: Deck?
    @State private var newName = ""
    @State private var deleting: Deck?
    /// 여러 장 선택. 클릭 = 한 장, ⌘클릭 = 토글, ⇧클릭 = 범위 추가, 빈 곳에서 끌기 = 러버밴드.
    @State private var selectedCards: Set<Int> = []
    /// ⇧클릭 범위의 시작점 (마지막으로 클릭한 카드)
    @State private var anchor: Int?
    @State private var marquee: CGRect?
    @State private var marqueeBase: Set<Int> = []
    @State private var frames = FrameStore()
    @State private var showInspector = true
    /// 융합 소재 링크로 이동 중인 카드: 범위를 바꾸면 onChange 가 선택을 비우므로 그 뒤에 고른다
    @State private var jumpTarget: Int?
    @State private var scrollTarget: Int?
    @State private var confirmSellLast = false
    @State private var confirmSellDuplicates = false
    @State private var confirmFuse = false
    /// 0 = 모든 등급, 1~5 = CardInfo.tier
    @State private var tierFilter = 0
    /// "" = 모든 종류, 아니면 CardInfo.kind 또는 소환법 (CardInfo.matches)
    @State private var kindFilter = ""
    @State private var search = ""
    @State private var showUnowned = true  // 기억하지 않고 창을 열 때마다 켠다
    @AppStorage("dex.sort") private var sort = DexSort.pack
    /// 마지막으로 고른 사이드바 항목과 연 시각. 그날 처음 열면 "전체"로 시작한다
    @AppStorage("dex.scope") private var savedScope = ""
    @AppStorage("dex.scopeDay") private var savedDay = 0.0  // 마지막으로 연 시각(timeIntervalSince1970)

    var body: some View {
        let game = model.game
        // 카드 목록은 6천 장을 필터·정렬하므로 한 번 그릴 때 한 번만 계산해 아래에서 같이 쓴다
        let tiered = tierEntries
        let entries = visible(tiered)
        NavigationSplitView {
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
            .navigationSplitViewColumnWidth(min: 220, ideal: 250)
        } detail: {
            // .scrollPosition(id:) 는 스크롤 중에도 값을 계속 써서 줄마다 창 전체를 다시 계산하므로, 이동할 때만 쓰는 ScrollViewReader 로
            ScrollView { ScrollViewReader { proxy in
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 12)], spacing: 14) {
                    ForEach(entries, id: \.number) { entry in
                        cell(number: entry.number, cid: entry.cid, label: entry.label)
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
                } else if entries.isEmpty, !query.isEmpty, scope != .all {
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
            .inspector(isPresented: $showInspector) {
                detail.inspectorColumnWidth(min: 240, ideal: 260)
            }
            .toolbar {
                let dup = model.game.duplicatesValue
                Button { confirmSellDuplicates = true } label: {
                    Label("중복 모두 팔기", systemImage: "dollarsign.circle").labelStyle(.titleAndIcon)
                }
                .help("카드마다 1장\(model.game.state.fusionOnly ? ", 융합 소재는 필요한 장 수" : "")만 남기고 모두 팔아요 (\(dup.count)장 · +\(coinText(dup.coins)))")
                .disabled(dup.count == 0)
                .confirmationDialog("중복 \(dup.count)장을 팔까요?", isPresented: $confirmSellDuplicates) {
                    Button("+\(coinText(dup.coins))에 판매") { model.sellDuplicates() }
                } message: {
                    Text(model.game.state.fusionOnly ? "카드마다 1장씩, 융합 소재는 필요한 장 수만큼 남아서 컬렉션은 그대로예요." : "카드마다 1장씩은 남아서 컬렉션은 그대로예요.")
                }
                // 러버밴드는 보이는 셀만 잡으니, 필터된 목록 전체는 이걸로
                Button {
                    selectedCards = Set(entries.map(\.cid))
                    showInspector = true
                } label: {
                    Label("전체 선택", systemImage: "checklist")
                }
                .keyboardShortcut("a")
                .help("지금 보이는 카드 모두 선택 (⌘A)")
                .disabled(entries.isEmpty)
                Button { showInspector.toggle() } label: { Label("정보", systemImage: "sidebar.trailing") }
            }
        }
    }

    private var filterBar: some View {
        HStack(spacing: 14) {
            Picker("종류", selection: $kindFilter) {
                Text("모든 종류").tag("")
                Divider()
                ForEach(["몬스터", "마법", "함정"], id: \.self) { Text($0).tag($0) }
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

    /// "어둠 · ★7 · 드래곤족/융합/효과" (랭크·링크는 "랭크 4"·"링크 4", 펜듈럼은 "P스케일 2" 추가). 없는 칸은 뺀다.
    private func summary(_ card: CardInfo) -> String {
        var parts: [String] = []
        if let attr = card.attr { parts.append(attr) }
        if let level = card.level { parts.append(card.levelName == "레벨" ? "★\(level)" : "\(card.levelName) \(level)") }
        if let scale = card.scale { parts.append("P스케일 \(scale)") }
        if let type = card.type { parts.append(type) }
        return parts.joined(separator: " · ")
    }

    private var title: String {
        switch scope {
        case .favorites?: "즐겨찾기"
        case .pack(let i)? where model.db.packs.indices.contains(i): model.db.packs[i].name
        case .deck(let id)?: model.game.deck(id)?.name ?? "덱"
        default: "전체"
        }
    }

    private func subtitle(_ all: [(number: Int, cid: Int, label: String)]) -> String {
        if case .deck(let id)? = scope, let deck = model.game.deck(id) {
            let p = model.game.deckProgress(deck)
            return "\(p.owned) / \(p.total)장 보유 · 메인 덱 \(Balance.deckSize.lowerBound)~\(Balance.deckSize.upperBound)장"
        }
        let owned = all.filter { model.game.copies($0.cid) > 0 }.count
        return "\(owned) / \(all.count)장 보유"
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

    /// 화면에 보일 카드: 등급 필터 → 미보유 숨기기 → 정렬. 같은 값이면 팩 순번 순. (body 밖 동작용, body 는 한 번 계산한 값을 쓴다)
    private var entries: [(number: Int, cid: Int, label: String)] { visible(tierEntries) }

    private func visible(_ tiered: [(number: Int, cid: Int, label: String)]) -> [(number: Int, cid: Int, label: String)] {
        let game = model.game
        let list = tiered.filter { showUnowned || game.copies($0.cid) > 0 }
        let tier = { (e: (number: Int, cid: Int, label: String)) in model.db.tier(e.cid) }
        // 카드 목록은 바뀌지 않으니 이름 순위는 처음 이름순으로 볼 때 한 번만 만든다 (비교마다 문자열을 대면 6천 장에 ~50ms)
        if sort == .name, Self.nameRank.isEmpty { Self.nameRank = CardDB.nameRanks(model.db.cards) }
        let name = { (cid: Int) in Self.nameRank[cid] ?? .max }
        return list.sorted { a, b in
            switch sort {
            case .pack: break
            case .tierDesc: if tier(a) != tier(b) { return tier(a) > tier(b) }
            case .tierAsc: if tier(a) != tier(b) { return tier(a) < tier(b) }
            case .name: if name(a.cid) != name(b.cid) { return name(a.cid) < name(b.cid) }
            case .copies: if game.copies(a.cid) != game.copies(b.cid) { return game.copies(a.cid) > game.copies(b.cid) }
            }
            return a.number < b.number
        }
    }

    /// number 는 등급 필터·정렬과 상관없이 팩(또는 전체) 안 순번.
    /// 띄어쓰기는 무시한다 ("푸른눈" 으로도 "푸른 눈의 백룡" 이 찾아진다)
    private var query: String { search.replacingOccurrences(of: " ", with: "") }

    private var tierEntries: [(number: Int, cid: Int, label: String)] {
        let db = model.db
        // 전체·즐겨찾기·덱: 팩 순서대로, 재수록은 처음 나온 팩 기준 한 번만
        var seen = Set<Int>()
        let all = { db.packs.flatMap(\.cards).filter { seen.insert($0).inserted } }
        let cards: [Int] = switch scope {
        case .pack(let i)? where db.packs.indices.contains(i): db.packs[i].cards
        case .favorites?: all().filter { model.game.state.favorites.contains($0) }
        case .deck(let id)?:
            { let inDeck = model.game.deck(id)?.cards ?? [:]; return all().filter { inDeck[$0] != nil } }()
        default: all()
        }
        return cards.enumerated()
            .filter { tierFilter == 0 || db.tier($0.element) == tierFilter }
            .filter { kindFilter.isEmpty || db.cards[$0.element]?.matches(kind: kindFilter) == true }
            .filter { query.isEmpty || (db.cards[$0.element]?.name ?? "").replacingOccurrences(of: " ", with: "").localizedStandardContains(query) }
            .map { ($0.offset + 1, $0.element, db.cards[$0.element]?.rarity ?? "N") }
    }

    /// 보고 있는 덱 (덱 화면이 아니면 nil)
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

    private var deckID: UUID? { if case .deck(let id)? = scope { id } else { nil } }

    /// 같은 소재가 반복되면 한 줄로 ("사이버 드래곤 × 3"). "× N" 조건의 count 도 곱한다
    private func grouped(_ materials: [Material]) -> [(material: Material, n: Int)] {
        materials.reduce(into: []) { acc, m in
            if acc.last?.material == m { acc[acc.count - 1].n += m.count ?? 1 } else { acc.append((m, m.count ?? 1)) }
        }
    }

    /// 융합 확인창: "사이버 드래곤 3장, 커스 오브 드래곤 1장"
    private func consumed(_ materials: [Material]) -> String {
        grouped(materials).compactMap { g in g.material.cid.flatMap { model.db.cards[$0]?.name }.map { "\($0) \(g.n)장" } }
            .joined(separator: ", ")
    }

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

    private func cell(number: Int, cid: Int, label: String) -> some View {
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
        // 사이드바 덱 줄에 끌어다 놓는다. 페이로드는 cid 를 쉼표로 이은 문자열 (선택된 카드를 끌면 선택 전체).
        .draggable(targets(cid).sorted().map(String.init).joined(separator: ",")) {
            DragPreview(db: model.db, cids: targets(cid).sorted())
        }
        .contextMenu { deckMenu(targets(cid), inDeck: deckID) }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("grid")) } action: { frames.map[cid] = $0 }
        .onDisappear { frames.map[cid] = nil }
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
        Button { model.removeFromDeck(deck, cid) } label: {
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
                cids.forEach { model.removeFromDeck(deck, $0) }
                selectedCards = selectedCards.filter { model.game.deck(deck)?.cards[$0] != nil }  // 0장이 된 카드는 선택에서도 뺀다
            }
        } else {
            let decks = model.game.state.decks
            if decks.isEmpty {
                Button("새 덱에 추가\(many)") { add(model.addDeck().id, cids) }
            } else {
                Menu("덱에 추가\(many)") {
                    ForEach(decks) { d in
                        let p = model.game.deckProgress(d)
                        Button("\(d.name) · \(p.owned)/\(p.total)") { add(d.id, cids) }
                    }
                }
            }
        }
    }

    /// 덱에 1장씩 넣고, 하나도 못 넣으면(3장 한도) 비프.
    private func add(_ deck: UUID, _ cids: Set<Int>) {
        if !cids.map({ model.addToDeck(deck, $0) }).contains(true) { NSSound.beep() }
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
                Button { scope = .deck(model.addDeck().id) } label: { Image(systemName: "plus") }
                    .buttonStyle(.plain)
                    .help("새 덱")
            }
            .padding(.leading, 3).padding(.trailing, 6)  // 시대 헤더와 같은 여백
        }
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

    @ViewBuilder private var detail: some View {
        if selectedCards.count > 1 {
            ContentUnavailableView {
                Label("\(selectedCards.count)장 선택됨", systemImage: "rectangle.on.rectangle")
            } description: {
                Text("왼쪽 덱 이름으로 끌어다 놓거나 아래에서 덱을 고르세요")
            } actions: {
                deckMenu(selectedCards, inDeck: deckID)
            }
        } else if let cid = selectedCards.first, let card = model.db.cards[cid] {
            let n = model.game.copies(cid)
            Form {
                CardImageView(db: model.db, cid: cid, size: .full, owned: n > 0)
                    .frame(maxWidth: .infinity)
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                    .listRowSeparator(.hidden)
                Section {
                    Text(card.name).font(.title3.weight(.semibold))
                    // 속성·레벨·종류 한 줄, ATK/DEF 한 줄로 짧게
                    VStack(alignment: .leading, spacing: 3) {
                        Text(summary(card))
                        if let atk = card.atk {
                            Text(card.def.map { "ATK \(atk) / DEF \($0)" } ?? "ATK \(atk)").monospacedDigit()
                        }
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                }
                if let pendulum = card.pendulum {
                    Section("펜듈럼 효과") { Text(pendulum).font(.callout).textSelection(.enabled) }
                }
                if let materials = card.materials {
                    Section("융합 소재") {
                        ForEach(Array(grouped(materials).enumerated()), id: \.offset) { _, g in
                            let suffix = g.n > 1 ? " × \(g.n)" : ""
                            if let mcid = g.material.cid, let name = model.db.cards[mcid]?.name {
                                HStack {
                                    Button(name + suffix) { jump(to: mcid) }.buttonStyle(.link)
                                    Spacer()
                                    Text("보유 \(model.game.copies(mcid))").foregroundStyle(.secondary).monospacedDigit()
                                }
                            } else if let name = g.material.name {
                                Text(name + suffix).foregroundStyle(.secondary).help("정규 부스터 100팩에 없는 카드예요")
                            } else {
                                Text((g.material.rule ?? "") + suffix).foregroundStyle(.secondary)
                            }
                        }
                        // 설정이 켜져 있고 소재를 다 아는 융합이면 여기서 만든다
                        if model.game.state.fusionOnly, model.game.fusionMaterials(cid) != nil {
                            let can = model.game.canFuse(cid)
                            let why = !model.game.hasFusionSpell ? "「융합」 마법 카드가 있어야 해요" : can ? "소재 카드를 소비해 1장 만들어요" : "소재 카드가 모자라요"
                            Button { confirmFuse = true } label: { Label("융합", systemImage: "arrow.triangle.merge") }
                                .buttonStyle(.glass)
                                .buttonBorderShape(.capsule)
                                .controlSize(.small)
                                .disabled(!can)
                                .help(why)
                                .confirmationDialog("\(card.name) 융합", isPresented: $confirmFuse) {
                                    Button("융합") { model.fuse(cid) }
                                } message: {
                                    Text("\(consumed(materials))을 소비해요. 0장이 되는 소재는 컬렉션에서 빠져요.")
                                }
                            if !model.game.hasFusionSpell {
                                Button("「융합」 마법 카드가 1장 있어야 해요 (소비되지 않아요)") { jump(to: CardDB.fusionSpell) }
                                    .buttonStyle(.link).font(.caption)
                            }
                        }
                    }
                }
                if !card.text.isEmpty {  // 바닐라 융합은 소재 줄을 떼면 효과가 없다
                    Section {
                        Text(card.text).font(.callout).textSelection(.enabled)
                    }
                }
                // 보유와 판매는 한 줄로 묶는다
                Section {
                    let price = model.game.sellPrice(cid)
                    HStack {
                        Text("보유 \(n)장").monospacedDigit()
                        Spacer()
                        Button {
                            if n == 1 { confirmSellLast = true } else { model.sell(cid) }
                        } label: {
                            Label("1장 판매 · +\(coinText(price))", systemImage: "dollarsign.circle")
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                        .controlSize(.small)
                        .disabled(n == 0)
                        .confirmationDialog("마지막 1장을 팔까요?", isPresented: $confirmSellLast) {
                            Button("+\(coinText(price))에 판매", role: .destructive) { model.sell(cid) }
                        } message: {
                            Text("컬렉션에서 빠지고 다시 모아야 해요.")
                        }
                    }
                }
                Section("수록 팩") {
                    ForEach(packs(cid), id: \.name) { item in
                        LabeledContent(item.name) {
                            RarityPill(label: item.label, owned: n > 0, size: 11)
                        }
                    }
                }
            }
            .formStyle(.grouped)
        } else {
            ContentUnavailableView("카드를 선택하세요", systemImage: "rectangle.portrait.on.rectangle.portrait",
                                   description: Text("카드를 누르면 자세한 정보가 여기 나와요"))
        }
    }

    private func packs(_ cid: Int) -> [(name: String, label: String)] {
        let label = model.db.cards[cid]?.rarity ?? "N"
        return model.db.packs.filter { $0.cards.contains(cid) }.map { ($0.name, label) }
    }
}

/// 사이드바의 시대(DM/GX) 묶음. 헤더를 눌러 접고 펴며, 접힘 상태는 다음 실행에도 기억한다.
private struct DexEraSection<Item: View>: View {
    @EnvironmentObject var model: AppModel
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
        let owned = packs.reduce(0) { $0 + game.progress($1).owned }
        let total = packs.reduce(0) { $0 + game.progress($1).total }
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
    @EnvironmentObject var model: AppModel
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
            let added = items.flatMap { $0.split(separator: ",") }.compactMap { Int($0) }.filter { model.addToDeck(deck.id, $0) }
            if added.isEmpty { NSSound.beep() }
            return !added.isEmpty
        } isTargeted: { targeted = $0 }
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

/// 사이드바 선택: 전체 · 즐겨찾기 · 팩 · 덱
enum DexScope: Hashable {
    case all, favorites
    case pack(Int)
    case deck(UUID)

    /// UserDefaults 저장용: "all", "favorites", "pack:3", "deck:<UUID>"
    var key: String {
        switch self {
        case .all: "all"
        case .favorites: "favorites"
        case .pack(let i): "pack:\(i)"
        case .deck(let id): "deck:\(id.uuidString)"
        }
    }

    init?(key: String) {
        let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
        switch (parts.first, parts.count) {
        case ("all", 1): self = .all
        case ("favorites", 1): self = .favorites
        case ("pack", 2): guard let i = Int(parts[1]) else { return nil }; self = .pack(i)
        case ("deck", 2): guard let id = UUID(uuidString: parts[1]) else { return nil }; self = .deck(id)
        default: return nil
        }
    }
}

enum DexSort: String, CaseIterable {
    case pack, tierDesc, tierAsc, name, copies

    var title: String {
        switch self {
        case .pack: "팩 순서"
        case .tierDesc: "높은 등급순"
        case .tierAsc: "낮은 등급순"
        case .name: "이름순"
        case .copies: "보유 많은 순"
        }
    }
}
