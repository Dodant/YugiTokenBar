#if os(Linux)
import Adwaita
import Foundation

/// Dialog body: the card's localized data and a one-copy sale (the last copy is always kept).
@MainActor struct LinuxCardContent: View {
    let cid: Int?
    let game: Game
    let sell: (Int) -> Void

    var view: Body {
        if let cid, let card = game.db.cards[cid] {
            let copies = game.copies(cid)
            ScrollView {
                VStack(spacing: 8) {
                    LinuxPicture(request: LinuxDexView.imageRequest(for: cid, game: game), size: .detail)
                        .frame(minWidth: 240, minHeight: 350)
                    Text(card.name).wrap().style("title-3").halign(.start)
                    Text(card.summary).wrap().halign(.start)
                    Text(card.rarity).halign(.start)
                    if let atk = card.atk { Text(card.def.map { "ATK \(atk) / DEF \($0)" } ?? "ATK \(atk)").halign(.start) }
                    if !card.text.isEmpty { Text(card.text).wrap().halign(.start) }
                    Text(L("보유 %lld장", .int(copies))).halign(.start)
                    Button(L("1장 판매 · +%@", .text(coinText(game.sellPrice(cid)))) ) { sell(cid) }
                        .linuxSmokeID("dex-sell-one")
                        .insensitive(copies < 2)
                }.padding()
            }
        }
    }
}
#endif
