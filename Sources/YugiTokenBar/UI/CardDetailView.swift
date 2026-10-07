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
            CardImageView(db: model.db, cid: cid, size: .full, owned: n > 0)
                .frame(maxWidth: .infinity)
                .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                .cardTilt(tier: model.db.tier(cid))
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
                                Button(name + suffix) { jump(mcid) }.buttonStyle(.link)
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
                        let why: LocalizedStringKey = !model.game.hasFusionSpell ? "「융합」 마법 카드가 있어야 해요" : can ? "소재 카드를 소비해 1장 만들어요" : "소재 카드가 모자라요"
                        HStack(spacing: 4) {
                            Spacer()
                            if !model.game.hasFusionSpell {  // 누르면 「융합」 카드로 이동
                                Image(systemName: "questionmark.circle")
                                    .foregroundStyle(.secondary)
                                    .hoverHint("「융합」 마법 카드가 1장 있어야 해요 (소비되지 않아요)")
                                    .onTapGesture { jump(CardDB.fusionSpell) }
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

    /// 같은 소재가 반복되면 한 줄로 ("사이버 드래곤 × 3"). "× N" 조건의 count 도 곱한다
    private func grouped(_ materials: [Material]) -> [(material: Material, n: Int)] {
        materials.reduce(into: []) { acc, m in
            if acc.last?.material == m { acc[acc.count - 1].n += m.count ?? 1 } else { acc.append((m, m.count ?? 1)) }
        }
    }

    /// 융합 확인창: "사이버 드래곤 3장, 커스 오브 드래곤 1장"
    private func consumed(_ materials: [Material]) -> String {
        grouped(materials).compactMap { g in g.material.cid.flatMap { model.db.cards[$0]?.name }.map { String(localized: "\($0) \(g.n)장") } }
            .joined(separator: ", ")
    }

    private func packs(_ cid: Int) -> [(name: String, label: String)] {
        let label = model.db.cards[cid]?.rarity ?? "N"
        return model.db.packs.filter { $0.cards.contains(cid) }.map { ($0.name, label) }
    }
}
