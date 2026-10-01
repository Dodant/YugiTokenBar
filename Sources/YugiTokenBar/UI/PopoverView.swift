import SwiftUI

struct PopoverView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if model.showShop {
                ShopView(onOpen: { show("pack") })
            } else {
                summary
            }
        }
        .padding(12)
        .frame(width: 340)
        .onAppear { model.markSeen() }
    }

    private var header: some View {
        let state = model.game.state
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("YugiTokenBar").font(.headline)
                Spacer()
                Text("🪙 \(state.coins.formatted())").font(.headline).foregroundStyle(.yellow)
            }
            Text("다음 무료 카드까지 \(shortTokens(Balance.tokensPerFreeCard - state.dropProgress))")
                .font(.caption)
            ProgressView(value: Double(state.dropProgress), total: Double(Balance.tokensPerFreeCard))
        }
    }

    private var summary: some View {
        let game = model.game
        return VStack(alignment: .leading, spacing: 8) {
            Text("최근 획득").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(Array(game.state.log.prefix(5).enumerated()), id: \.offset) { _, entry in
                    CardImageView(db: game.db, cid: entry.cid)
                        .frame(width: 56)
                        .help(game.db.cards[entry.cid]?.name ?? "")
                }
                if game.state.log.isEmpty {
                    Text("아직 카드가 없어요").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("팩 구매").font(.caption).foregroundStyle(.secondary)
            PackRow(index: game.state.unlocked - 1, onOpen: { show("pack") })
            Button("상점 전체 보기") { model.showShop = true }
                .frame(maxWidth: .infinity)
            Button("📖 도감 열기 (\(game.ownedDistinct) / \(game.db.allCIDs.count))") { show("dex") }
                .frame(maxWidth: .infinity)
            Divider()
            Button("종료") { NSApp.terminate(nil) }.font(.caption)
        }
    }

    private func show(_ id: String) {
        openWindow(id: id)
        NSApp.activate(ignoringOtherApps: true)
    }
}

func shortTokens(_ n: Int) -> String {
    n >= 1_000_000 ? String(format: "%.1fM", Double(n) / 1e6) : String(format: "%.0fK", Double(n) / 1e3)
}
