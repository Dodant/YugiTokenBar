import SwiftUI

struct ShopView: View {
    @EnvironmentObject var model: AppModel
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button("← 돌아가기") { model.showShop = false }.buttonStyle(.link)
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(model.db.packs.indices, id: \.self) { i in
                        PackRow(index: i, onOpen: onOpen)
                    }
                }
            }
            .frame(height: 420)
        }
    }
}

struct PackRow: View {
    @EnvironmentObject var model: AppModel
    let index: Int
    let onOpen: () -> Void

    var body: some View {
        let game = model.game
        let pack = game.db.packs[index]
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3)
                .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 26, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(game.isUnlocked(index) ? pack.name : "🔒 \(pack.name)").lineLimit(1)
                Text(subtitle(game)).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if game.isUnlocked(index) && !game.isComplete(index) {
                buyButton(1)
                buyButton(5)
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))
        .opacity(game.isUnlocked(index) ? 1 : 0.5)
    }

    private func subtitle(_ game: Game) -> String {
        let pack = game.db.packs[index]
        let p = game.progress(index)
        if game.isComplete(index) { return "완료 · \(p.owned)/\(p.total)" }
        if !game.isUnlocked(index) {
            return "\(game.db.packs[index - 1].name) 50% 달성 시 해금 · 보유 \(p.owned)"
        }
        return "\(pack.date.prefix(4)) · 도감 \(p.owned)/\(p.total)"
    }

    private func buyButton(_ n: Int) -> some View {
        Button("\(n)팩") {
            if model.buy(pack: index, count: n) { onOpen() }
        }
        .disabled(!model.game.canBuy(index, count: n))
        .help("\((Balance.packPrice * n).formatted())코인")
    }
}
