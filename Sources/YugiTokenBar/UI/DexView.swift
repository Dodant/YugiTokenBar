import SwiftUI

struct DexView: View {
    @EnvironmentObject var model: AppModel
    /// -1 = 전체, -2 = 즐겨찾기
    @State private var selectedPack: Int? = 0
    @State private var selectedCard: Int?
    @State private var hoveredCard: Int?
    @State private var showInspector = true
    @State private var confirmSellLast = false
    @State private var confirmSellDuplicates = false
    /// 0 = 모든 등급, 1~4 = PackCard.tier
    @State private var tierFilter = 0
    /// "" = 모든 종류, 아니면 CardInfo.kind
    @State private var kindFilter = ""
    @State private var search = ""
    @AppStorage("dex.showUnowned") private var showUnowned = true
    @AppStorage("dex.sort") private var sort = DexSort.pack

    var body: some View {
        let game = model.game
        NavigationSplitView {
            List(selection: $selectedPack) {
                Label {
                    HStack {
                        Text("전체")
                        Spacer()
                        Text("\(game.ownedDistinct) / \(game.db.allCIDs.count)").foregroundStyle(.secondary).monospacedDigit()
                    }
                } icon: {
                    Image(systemName: "square.grid.2x2")
                }
                .tag(-1)
                Label {
                    HStack {
                        Text("즐겨찾기")
                        Spacer()
                        Text("\(game.state.favorites.count)").foregroundStyle(.secondary).monospacedDigit()
                    }
                } icon: {
                    Image(systemName: "star.fill").foregroundStyle(.yellow)
                }
                .tag(-2)
                ForEach(game.db.eras, id: \.name) { era in
                    DexEraSection(name: era.name, packs: era.packs) { i in packItem(game, i) }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 220, ideal: 250)
        } detail: {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 12)], spacing: 14) {
                    ForEach(entries, id: \.number) { entry in
                        cell(number: entry.number, cid: entry.cid, label: entry.label)
                    }
                }
                .padding(16)
            }
            // ponytail: macOS 26 툴바 유리 그룹 안에선 메뉴 Picker 글자가 안 그려지고 체크박스가 뭉개져서 그리드 위 막대에 둔다
            .safeAreaInset(edge: .top, spacing: 0) { filterBar }
            .overlay {
                if entries.isEmpty, selectedPack == -2, model.game.state.favorites.isEmpty {
                    ContentUnavailableView("즐겨찾기한 카드가 없어요", systemImage: "star",
                                           description: Text("카드에 마우스를 올리고 오른쪽 위 ☆를 눌러 보세요"))
                } else if entries.isEmpty {
                    ContentUnavailableView(showUnowned ? "조건에 맞는 카드가 없어요" : "보유한 카드가 없어요",
                                           systemImage: "line.3.horizontal.decrease.circle",
                                           description: Text(showUnowned ? "다른 팩이나 종류·등급을 골라 보세요" : "미보유 카드 포함을 켜면 전부 보여요"))
                }
            }
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
        if selectedPack == -2 { return "즐겨찾기" }
        guard let i = selectedPack, i >= 0 else { return "전체" }
        return model.db.packs[i].name
    }

    private var subtitle: String {
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
        let cards: [PackCard]
        if let i = selectedPack, i >= 0 {
            cards = db.packs[i].cards
        } else {
            // 전체: 팩 순서대로, 재수록은 처음 나온 팩 기준 한 번만
            var seen = Set<Int>()
            cards = db.packs.flatMap(\.cards).filter { seen.insert($0.cid).inserted }
                .filter { selectedPack != -2 || model.game.state.favorites.contains($0.cid) }
        }
        return cards.enumerated()
            .filter { tierFilter == 0 || $0.element.tier == tierFilter }
            .filter { kindFilter.isEmpty || db.cards[$0.element.cid]?.kind == kindFilter }
            .filter { query.isEmpty || (db.cards[$0.element.cid]?.name ?? "").replacingOccurrences(of: " ", with: "").localizedStandardContains(query) }
            .map { ($0.offset + 1, $0.element.cid, $0.element.label) }
    }

    private func cell(number: Int, cid: Int, label: String) -> some View {
        let n = model.game.copies(cid)
        let selected = selectedCard == cid
        return VStack(spacing: 4) {
            CardImageView(db: model.db, cid: cid, owned: n > 0)
                .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.accentColor, lineWidth: selected ? 3 : 0))
                .overlay(alignment: .topTrailing) { star(cid) }
            HStack(spacing: 4) {
                Text(String(format: "%03d", number)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                RarityPill(label: label, owned: n > 0)
                if n > 1 { Text("×\(n)").fontWeight(.semibold) }
            }
            .font(.caption2)
            .monospacedDigit()
        }
        .contentShape(Rectangle())
        .onHover { hoveredCard = $0 ? cid : (hoveredCard == cid ? nil : hoveredCard) }
        .help(model.db.cards[cid]?.name ?? "")
        .onTapGesture {
            selectedCard = cid
            showInspector = true
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
        if let cid = selectedCard, let card = model.db.cards[cid] {
            let n = model.game.copies(cid)
            Form {
                CardImageView(db: model.db, cid: cid, size: .full, owned: n > 0)
                    .frame(maxWidth: .infinity)
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                    .listRowSeparator(.hidden)
                Section {
                    Text(card.name).font(.title3.weight(.semibold))
                    if let attr = card.attr { LabeledContent("속성", value: attr) }
                    if let level = card.level { LabeledContent("레벨", value: "★\(level)") }
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
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .disabled(n == 0)
                    .confirmationDialog("마지막 1장을 팔까요?", isPresented: $confirmSellLast) {
                        Button("+\(coinText(price))에 판매", role: .destructive) { model.sell(cid) }
                    } message: {
                        Text("컬렉션에서 빠지고 다시 모아야 해요.")
                    }
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
                ForEach(packs, id: \.self) { i in item(i).tag(i) }
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
