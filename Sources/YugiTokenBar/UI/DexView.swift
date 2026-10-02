import SwiftUI

struct DexView: View {
    @EnvironmentObject var model: AppModel
    /// -1 = 전체
    @State private var selectedPack: Int? = 0
    @State private var selectedCard: Int?
    @State private var showInspector = true
    @State private var confirmSellLast = false
    @State private var confirmSellDuplicates = false
    /// 0 = 모든 등급, 1~4 = PackCard.tier
    @State private var tierFilter = 0

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
                Section("부스터 팩") {
                    ForEach(game.db.packs.indices, id: \.self) { i in
                        packItem(game, i).tag(i)
                    }
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
            .overlay {
                if entries.isEmpty {
                    ContentUnavailableView("이 등급 카드가 없어요", systemImage: "line.3.horizontal.decrease.circle",
                                           description: Text("다른 팩이나 등급을 골라 보세요"))
                }
            }
            .navigationTitle(title)
            .navigationSubtitle(subtitle)
            .inspector(isPresented: $showInspector) {
                detail.inspectorColumnWidth(min: 240, ideal: 260)
            }
            .toolbar {
                Picker("등급", selection: $tierFilter) {
                    Text("모든 등급").tag(0)
                    Divider()
                    Text("N 노멀").tag(1)
                    Text("R 레어").tag(2)
                    Text("SR 슈퍼").tag(3)
                    Text("UR 울트라").tag(4)
                }
                .pickerStyle(.menu)
                .help("등급별로 보기")
                let dup = model.game.duplicatesValue
                Button { confirmSellDuplicates = true } label: {
                    Label("중복 모두 팔기", systemImage: "dollarsign.circle").labelStyle(.titleAndIcon)
                }
                .help("2장째 카드를 모두 팔아요 (\(dup.count)장 · +\(dup.coins.formatted()) 코인)")
                .disabled(dup.count == 0)
                .confirmationDialog("중복 \(dup.count)장을 팔까요?", isPresented: $confirmSellDuplicates) {
                    Button("+\(dup.coins.formatted()) 코인에 판매") { model.sellDuplicates() }
                } message: {
                    Text("카드마다 1장씩은 남아서 컬렉션은 그대로예요.")
                }
                Button { showInspector.toggle() } label: { Label("정보", systemImage: "sidebar.trailing") }
            }
        }
    }

    private var title: String {
        guard let i = selectedPack, i >= 0 else { return "전체" }
        return model.db.packs[i].name
    }

    private var subtitle: String {
        let owned = entries.filter { model.game.copies($0.cid) > 0 }.count
        return "\(owned) / \(entries.count)장 보유"
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

    /// number 는 등급 필터와 상관없이 팩(또는 전체) 안 순번.
    private var entries: [(number: Int, cid: Int, label: String)] {
        let db = model.db
        let cards: [PackCard]
        if let i = selectedPack, i >= 0 {
            cards = db.packs[i].cards
        } else {
            // 전체: 팩 순서대로, 재수록은 처음 나온 팩 기준 한 번만
            var seen = Set<Int>()
            cards = db.packs.flatMap(\.cards).filter { seen.insert($0.cid).inserted }
        }
        return cards.enumerated()
            .filter { tierFilter == 0 || $0.element.tier == tierFilter }
            .map { ($0.offset + 1, $0.element.cid, $0.element.label) }
    }

    private func cell(number: Int, cid: Int, label: String) -> some View {
        let n = model.game.copies(cid)
        let selected = selectedCard == cid
        return VStack(spacing: 4) {
            CardImageView(db: model.db, cid: cid, owned: n > 0)
                .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.accentColor, lineWidth: selected ? 3 : 0))
            HStack(spacing: 4) {
                Text(String(format: "%03d", number)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                RarityPill(label: label, owned: n > 0)
                if n > 0 { Text("×\(n)").fontWeight(.semibold) }
            }
            .font(.caption2)
            .monospacedDigit()
        }
        .contentShape(Rectangle())
        .help(model.db.cards[cid]?.name ?? "")
        .onTapGesture {
            selectedCard = cid
            showInspector = true
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
                    LabeledContent("보유", value: "\(n) / \(Balance.maxCopies)")
                    let price = model.game.sellPrice(cid)
                    Button {
                        if n == 1 { confirmSellLast = true } else { model.sell(cid) }
                    } label: {
                        Label("1장 판매 · +\(price.formatted()) 코인", systemImage: "dollarsign.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .disabled(n == 0)
                    .confirmationDialog("마지막 1장을 팔까요?", isPresented: $confirmSellLast) {
                        Button("+\(price.formatted()) 코인에 판매", role: .destructive) { model.sell(cid) }
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
