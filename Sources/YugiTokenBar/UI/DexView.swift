import SwiftUI

struct DexView: View {
    @EnvironmentObject var model: AppModel
    /// -1 = 전체
    @State private var selectedPack: Int? = 0
    @State private var selectedCard: Int?

    var body: some View {
        let game = model.game
        HStack(spacing: 0) {
            List(selection: $selectedPack) {
                Text("전체 · \(game.ownedDistinct) / \(game.db.allCIDs.count)").tag(-1)
                ForEach(game.db.packs.indices, id: \.self) { i in
                    packItem(game, i).tag(i)
                }
            }
            .frame(width: 210)

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 6)], spacing: 6) {
                    ForEach(Array(entries.enumerated()), id: \.offset) { n, entry in
                        cell(number: n + 1, cid: entry.cid, label: entry.label)
                    }
                }
                .padding(10)
            }

            Divider()
            detail.frame(width: 230)
        }
    }

    private func packItem(_ game: Game, _ i: Int) -> some View {
        let pack = game.db.packs[i]
        let p = game.progress(i)
        return VStack(alignment: .leading, spacing: 2) {
            Text(game.isUnlocked(i) ? pack.name : "🔒 \(pack.name)")
            Text("\(p.owned) / \(p.total) · \(pack.date.prefix(4))").font(.caption2).foregroundStyle(.secondary)
            ProgressView(value: Double(p.owned), total: Double(p.total)).controlSize(.mini)
        }
    }

    private var entries: [(cid: Int, label: String)] {
        let db = model.db
        if let i = selectedPack, i >= 0 { return db.packs[i].cards.map { ($0.cid, $0.label) } }
        // 전체: 팩 순서대로, 재수록은 처음 나온 팩 기준 한 번만
        var seen = Set<Int>()
        return db.packs.flatMap(\.cards).filter { seen.insert($0.cid).inserted }.map { ($0.cid, $0.label) }
    }

    private func cell(number: Int, cid: Int, label: String) -> some View {
        let n = model.game.copies(cid)
        return CardImageView(db: model.db, cid: cid, owned: n > 0)
            .overlay(alignment: .topLeading) {
                Text(String(format: "%03d", number))
                    .font(.system(size: 9)).foregroundStyle(.white)
                    .padding(2).background(.black.opacity(0.5))
            }
            .overlay(alignment: .bottomTrailing) {
                if n > 0 {
                    Text("\(label) ×\(n)")
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 3).background(.black.opacity(0.7))
                }
            }
            .help(model.db.cards[cid]?.name ?? "")
            .onTapGesture { selectedCard = cid }
    }

    @ViewBuilder private var detail: some View {
        if let cid = selectedCard, let card = model.db.cards[cid] {
            let n = model.game.copies(cid)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    CardImageView(db: model.db, cid: cid, size: .full, owned: n > 0)
                    Text(card.name).font(.headline)
                    Text([card.attr, card.level.map { "★\($0)" }, card.type].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                    if let atk = card.atk {
                        Text("공격력 \(atk) / 수비력 \(card.def ?? "-")").font(.caption)
                    }
                    Text(card.text).font(.caption).foregroundStyle(.secondary)
                    Text("\(packsText(cid)) · 보유 \(n)/\(Balance.maxCopies)")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .padding(10)
            }
        } else {
            Text("카드를 눌러 자세히 보기")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func packsText(_ cid: Int) -> String {
        model.db.packs.compactMap { pack in
            pack.cards.first { $0.cid == cid }.map { "\(pack.name) \($0.label)" }
        }.joined(separator: ", ")
    }
}
