import SwiftUI

/// 오른쪽 패널의 카드 한 장 정보: 이미지·효과·융합 소재(이동·융합)·보유와 판매·수록 팩
struct CardDetailView: View {
    @Environment(AppModel.self) private var model
    let cid: Int
    let card: CardInfo
    /// 융합 소재 링크·「융합」 안내를 누르면 그 카드로
    let jump: (Int) -> Void
    /// 융합했으면 연출을 띄운다
    let fused: (FusionShow) -> Void
    @State private var confirmSellLast = false
    @State private var confirmFuse = false

    var body: some View {
        let n = model.game.copies(cid)
        Form {
            // 미보유도 컬러로, 호버 기울기 없이
            CardImageView(db: model.db, cid: cid, size: .full)
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
                    if card.mask == true {  // 마스크드 히어로는 소재 줄이 없다: 조건 글 한 줄 밑에 정해진 HERO
                        Text("같은 속성(\(card.attr ?? ""))의 \"히어로\" 몬스터 1장").foregroundStyle(.secondary)
                    }
                    ForEach(Array(grouped(materials).enumerated()), id: \.offset) { _, g in
                        if let rule = g.rule {  // 조건 소재: 조건 글 밑에 정해진 카드 (카드가 없으면 못 만든다)
                            Text(rule + (g.cards.isEmpty && g.n > 1 ? " × \(g.n)" : "")).foregroundStyle(.secondary)
                        } else if let name = g.name {
                            Text(name + (g.n > 1 ? " × \(g.n)" : "")).foregroundStyle(.secondary).help("정규 부스터 100팩에 없는 카드예요")
                        }
                        ForEach(g.cards) { c in materialRow(c.cid, c.n > 1 ? " × \(c.n)" : "") }
                    }
                    // 설정이 켜져 있고 소재를 다 아는 융합(또는 마스크드 히어로)이면 여기서 만든다
                    if model.game.state.fusionOnly, card.craftable {
                        let can = model.game.canFuse(cid)
                        let spell = model.game.craftSpell(cid)
                        let hasSpell = model.game.copies(spell) > 0
                        let spellName = model.db.cards[spell]?.name ?? ""
                        let why: LocalizedStringKey = !hasSpell ? "「\(spellName)」 마법 카드가 있어야 해요" : can ? "소재 카드를 소비해 1장 만들어요" : "소재 카드가 모자라요"
                        HStack(spacing: 4) {
                            Spacer()
                            if !hasSpell {  // 누르면 「융합」(「마스크 체인지」) 카드로 이동
                                Image(systemName: "questionmark.circle")
                                    .foregroundStyle(.secondary)
                                    .hoverHint("「\(spellName)」 마법 카드가 1장 있어야 해요 (소비되지 않아요)")
                                    .onTapGesture { jump(spell) }
                            }
                            Button { confirmFuse = true } label: { Label("융합", systemImage: "arrow.triangle.merge") }
                                .buttonStyle(.glass)
                                .buttonBorderShape(.capsule)
                                .controlSize(.small)
                                .disabled(!can)
                                .help(why)
                                .confirmationDialog("\(card.name) 융합", isPresented: $confirmFuse) {
                                    Button("융합") {
                                        let mats = materials.flatMap { m in m.cid.map { Array(repeating: $0, count: m.count ?? 1) } ?? [] }  // 연출은 소재 줄 순서대로
                                        model.fuse(cid)
                                        fused(FusionShow(cid: cid, materials: mats))
                                    }
                                } message: {
                                    Text("\(consumed(materials))을 소비해요. 소재는 1장씩 남아 컬렉션에서 빠지지 않아요.")
                                }
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
                        Label("1장 판매 · +\(coinText(price))", systemImage: "c.circle")
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
    }

    /// "어둠 · ★7 · 드래곤족/융합/효과" (랭크·링크는 "랭크 4"·"링크 4", 펜듈럼은 "P스케일 2" 추가). 없는 칸은 뺀다.
    private func summary(_ card: CardInfo) -> String {
        var parts: [String] = []
        if let attr = card.attr { parts.append(attr) }
        if let level = card.level {
            let text = switch card.levelKind {
            case .level: "★\(level)"
            case .rank: String(localized: "랭크 \(level)")
            case .link: String(localized: "링크 \(level)")
            }
            parts.append(text)
        }
        if let scale = card.scale { parts.append(String(localized: "P스케일 \(scale)")) }
        if let type = card.type { parts.append(type) }
        return parts.joined(separator: " · ")
    }

    /// 소재 화면 묶음: 조건 글(rule)이나 100팩 밖 이름(name) 하나에 쓸 카드들. 같은 카드가 반복되면 "× N"("사이버 드래곤 × 3", count 도 곱한다),
    /// 같은 조건 글이 이어지는 줄(즈아크의 "1장씩 합계 4장")은 조건 하나에 카드 넷
    private struct MaterialGroup {
        struct Card: Identifiable { let cid: Int; var n: Int; var id: Int { cid } }
        var rule: String?, name: String?
        var cards: [Card] = []
        var n = 0
    }

    private func grouped(_ materials: [Material]) -> [MaterialGroup] {
        var groups: [MaterialGroup] = []
        for m in materials {
            let n = m.count ?? 1
            let same = groups.last.map { g in m.rule != nil ? g.rule == m.rule : g.rule == nil && g.name == nil && m.name == nil && g.cards.first?.cid == m.cid } ?? false
            if !same { groups.append(MaterialGroup(rule: m.rule, name: m.name)) }
            groups[groups.count - 1].n += n
            if let cid = m.cid {
                if let i = groups[groups.count - 1].cards.firstIndex(where: { $0.cid == cid }) { groups[groups.count - 1].cards[i].n += n }
                else { groups[groups.count - 1].cards.append(.init(cid: cid, n: n)) }
            }
        }
        return groups
    }

    private func materialRow(_ mcid: Int, _ suffix: String) -> some View {
        HStack {
            Button((model.db.cards[mcid]?.name ?? "") + suffix) { jump(mcid) }.buttonStyle(.link)
            Spacer()
            Text("보유 \(model.game.copies(mcid))").foregroundStyle(.secondary).monospacedDigit()
        }
    }

    /// 융합 확인창: "사이버 드래곤 3장, 커스 오브 드래곤 1장" (소재 줄 순서, 같은 카드는 합쳐서)
    private func consumed(_ materials: [Material]) -> String {
        var order: [Int] = [], total: [Int: Int] = [:]
        for m in materials {
            guard let c = m.cid else { continue }
            if total[c] == nil { order.append(c) }
            total[c, default: 0] += m.count ?? 1
        }
        return order.compactMap { c in model.db.cards[c].map { String(localized: "\($0.name) \(total[c] ?? 0)장") } }.joined(separator: ", ")
    }

    private func packs(_ cid: Int) -> [(name: String, label: String)] {
        let label = model.db.cards[cid]?.rarity ?? "N"
        return model.db.packs.filter { $0.cards.contains(cid) }.map { ($0.name, label) }
    }
}
