import SwiftUI

struct DexView: View {
    @EnvironmentObject var model: AppModel
    @State private var scope: DexScope? = .pack(0)
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
    @State private var hoveredCard: Int?
    @State private var showInspector = true
    @State private var confirmSellLast = false
    @State private var confirmSellDuplicates = false
    /// 0 = 모든 등급, 1~4 = PackCard.tier
    @State private var tierFilter = 0
    /// "" = 모든 종류, 아니면 CardInfo.kind
    @State private var kindFilter = ""
    @State private var search = ""
    @State private var showUnowned = true  // 기억하지 않고 창을 열 때마다 켠다
    @AppStorage("dex.sort") private var sort = DexSort.pack

    var body: some View {
        let game = model.game
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
            ScrollView {
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
            }
            // ponytail: macOS 26 툴바 유리 그룹 안에선 메뉴 Picker 글자가 안 그려지고 체크박스가 뭉개져서 그리드 위 막대에 둔다
            .safeAreaInset(edge: .top, spacing: 0) { filterBar }
            .overlay {
                if case .deck(let id)? = scope, model.game.deck(id)?.cards.isEmpty ?? true {
                    ContentUnavailableView("덱이 비었어요", systemImage: "rectangle.stack.badge.plus",
                                           description: Text("팩에서 카드를 왼쪽 덱 이름으로 끌어다 놓거나, 카드를 우클릭해 추가하세요"))
                } else if entries.isEmpty, scope == .favorites, model.game.state.favorites.isEmpty {
                    ContentUnavailableView("즐겨찾기한 카드가 없어요", systemImage: "star",
                                           description: Text("카드에 마우스를 올리고 오른쪽 위 ☆를 눌러 보세요"))
                } else if entries.isEmpty {
                    ContentUnavailableView(showUnowned ? "조건에 맞는 카드가 없어요" : "보유한 카드가 없어요",
                                           systemImage: "line.3.horizontal.decrease.circle",
                                           description: Text(showUnowned ? "다른 팩이나 종류·등급을 골라 보세요" : "미보유 카드 포함을 켜면 전부 보여요"))
                }
            }
            .onChange(of: scope) { selectedCards = []; anchor = nil }
            // 설정에서 시대 범위를 줄여 보던 팩이 사라지면 "전체"로
            .onChange(of: model.db.packs.count) { if case .pack(let i)? = scope, i >= model.db.packs.count { scope = .all } }
            .navigationTitle(title)
            .navigationSubtitle(subtitle)
            .searchable(text: $search, placement: .toolbar, prompt: "카드 이름")
            .inspector(isPresented: $showInspector) {
                detail.inspectorColumnWidth(min: 240, ideal: 260)
            }
            .toolbar {
                let dup = model.game.duplicatesValue
                Button { confirmSellDuplicates = true } label: {
                    Label("중복 모두 팔기", systemImage: "dollarsign.circle").labelStyle(.titleAndIcon)
                }
                .help("카드마다 1장만 남기고 모두 팔아요 (\(dup.count)장 · +\(coinText(dup.coins)))")
                .disabled(dup.count == 0)
                .confirmationDialog("중복 \(dup.count)장을 팔까요?", isPresented: $confirmSellDuplicates) {
                    Button("+\(coinText(dup.coins))에 판매") { model.sellDuplicates() }
                } message: {
                    Text("카드마다 1장씩은 남아서 컬렉션은 그대로예요.")
                }
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
            }
            .fixedSize()
            Picker("등급", selection: $tierFilter) {
                Text("모든 등급").tag(0)
                Divider()
                Text("N 노멀").tag(1)
                Text("R 레어").tag(2)
                Text("SR 슈퍼").tag(3)
                Text("UR 울트라").tag(4)
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

    private var subtitle: String {
        if case .deck(let id)? = scope, let deck = model.game.deck(id) {
            let p = model.game.deckProgress(deck)
            return "\(p.owned) / \(p.total)장 보유 · 메인 덱 \(Balance.deckSize.lowerBound)~\(Balance.deckSize.upperBound)장"
        }
        let all = tierEntries
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

    /// 화면에 보일 카드: 등급 필터 → 미보유 숨기기 → 정렬. 같은 값이면 팩 순번 순.
    private var entries: [(number: Int, cid: Int, label: String)] {
        let game = model.game
        let list = tierEntries.filter { showUnowned || game.copies($0.cid) > 0 }
        let tier = { (e: (number: Int, cid: Int, label: String)) in (PackCard.labels.firstIndex(of: e.label) ?? 0) }
        let name = { (cid: Int) in model.db.cards[cid]?.name ?? "" }
        return list.sorted { a, b in
            switch sort {
            case .pack: break
            case .tierDesc: if tier(a) != tier(b) { return tier(a) > tier(b) }
            case .tierAsc: if tier(a) != tier(b) { return tier(a) < tier(b) }
            case .name:
                let c = name(a.cid).localizedStandardCompare(name(b.cid))
                if c != .orderedSame { return c == .orderedAscending }
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
        let all = { db.packs.flatMap(\.cards).filter { seen.insert($0.cid).inserted } }
        let cards: [PackCard] = switch scope {
        case .pack(let i)? where db.packs.indices.contains(i): db.packs[i].cards
        case .favorites?: all().filter { model.game.state.favorites.contains($0.cid) }
        case .deck(let id)?:
            { let inDeck = model.game.deck(id)?.cards ?? [:]; return all().filter { inDeck[$0.cid] != nil } }()
        default: all()
        }
        return cards.enumerated()
            .filter { tierFilter == 0 || $0.element.tier == tierFilter }
            .filter { kindFilter.isEmpty || db.cards[$0.element.cid]?.kind == kindFilter }
            .filter { query.isEmpty || (db.cards[$0.element.cid]?.name ?? "").replacingOccurrences(of: " ", with: "").localizedStandardContains(query) }
            .map { ($0.offset + 1, $0.element.cid, $0.element.label) }
    }

    /// 보고 있는 덱 (덱 화면이 아니면 nil)
    private var deckID: UUID? { if case .deck(let id)? = scope { id } else { nil } }

    /// 끌기·우클릭이 적용되는 카드들: 선택된 카드면 선택 전체, 아니면 그 카드만.
    private func targets(_ cid: Int) -> Set<Int> { selectedCards.contains(cid) ? selectedCards : [cid] }

    private func cell(number: Int, cid: Int, label: String) -> some View {
        let game = model.game
        // 덱 화면에선 덱에 넣은 장 수를 보여주고, 보유가 그보다 적으면 미보유처럼 흐리게(더 모아야 할 카드)
        let inDeck = deckID.flatMap { game.deck($0)?.cards[cid] }
        let n = inDeck ?? game.copies(cid)
        let owned = inDeck.map { game.copies(cid) >= $0 } ?? (n > 0)
        let selected = selectedCards.contains(cid)
        return VStack(spacing: 4) {
            CardImageView(db: model.db, cid: cid, owned: owned)
                .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.accentColor, lineWidth: selected ? 3 : 0))
                .overlay(alignment: .topTrailing) { star(cid) }
                .overlay(alignment: .topLeading) { if let deckID { minus(deckID, cid) } }
            Text(model.db.cards[cid]?.name ?? "")
                .font(.caption2).lineLimit(1).truncationMode(.tail)
                .foregroundStyle(owned ? .primary : .secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 4) {
                Text(String(format: "%03d", number)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                RarityPill(label: label, owned: owned)
                if n > 1 || inDeck != nil { Text("×\(n)").fontWeight(.semibold) }
            }
            .font(.caption2)
            .monospacedDigit()
        }
        .contentShape(Rectangle())
        .onHover { hoveredCard = $0 ? cid : (hoveredCard == cid ? nil : hoveredCard) }
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
    @ViewBuilder private func minus(_ deck: UUID, _ cid: Int) -> some View {
        if hoveredCard == cid {
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
        }
    }

    /// 즐겨찾기 별: 체크된 카드는 항상, 아니면 마우스를 올렸을 때만.
    @ViewBuilder private func star(_ cid: Int) -> some View {
        let on = model.game.state.favorites.contains(cid)
        if on || hoveredCard == cid {
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
                    if let attr = card.attr { LabeledContent("속성", value: attr) }
                    if let level = card.level { LabeledContent(card.levelName, value: card.levelName == "레벨" ? "★\(level)" : "\(level)") }
                    if let scale = card.scale { LabeledContent("P스케일", value: "\(scale)") }
                    if let type = card.type { LabeledContent("종류", value: type) }
                    if let atk = card.atk { LabeledContent("공격력 / 수비력", value: "\(atk) / \(card.def ?? "-")") }
                    LabeledContent("보유", value: "\(n)장")
                    let price = model.game.sellPrice(cid)
                    Button {
                        if n == 1 { confirmSellLast = true } else { model.sell(cid) }
                    } label: {
                        Label("1장 판매 · +\(coinText(price))", systemImage: "dollarsign.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .disabled(n == 0)
                    .confirmationDialog("마지막 1장을 팔까요?", isPresented: $confirmSellLast) {
                        Button("+\(coinText(price))에 판매", role: .destructive) { model.sell(cid) }
                    } message: {
                        Text("컬렉션에서 빠지고 다시 모아야 해요.")
                    }
                }
                if let pendulum = card.pendulum {
                    Section("펜듈럼 효과") { Text(pendulum).font(.callout).textSelection(.enabled) }
                }
                Section("효과") {
                    Text(card.text).font(.callout).textSelection(.enabled)
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
        model.db.packs.compactMap { pack in
            pack.cards.first { $0.cid == cid }.map { (pack.name, $0.label) }
        }
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

/// 화면에 보이는 셀의 프레임 (러버밴드 선택용). 클래스라 갱신해도 뷰를 다시 그리지 않는다.
private final class FrameStore {
    var map: [Int: CGRect] = [:]
}

/// 사이드바 선택: 전체 · 즐겨찾기 · 팩 · 덱
enum DexScope: Hashable {
    case all, favorites
    case pack(Int)
    case deck(UUID)
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
