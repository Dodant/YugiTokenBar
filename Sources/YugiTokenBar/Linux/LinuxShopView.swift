#if os(Linux)
import Adwaita
import CAdw
import Foundation

@MainActor struct LinuxShopView: View {
    let snapshot: LinuxSnapshot
    let model: LinuxModel

    var view: Body {
        if let opening = snapshot.opening {
            LinuxOpeningView(opening: opening, game: snapshot.game, close: model.closeOpening)
        } else {
            ScrollView {
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        Button(L("무료 카드 %lld", .int(snapshot.game.state.pendingFree))) { model.openFree() }
                            .linuxSmokeID("shop-free-cards")
                            .insensitive(snapshot.game.state.pendingFree == 0)
                        Button(L("무료 팩 %lld", .int(snapshot.game.state.freePacks))) { model.openFreePack() }
                            .linuxSmokeID("shop-free-pack")
                            .insensitive(snapshot.game.state.freePacks == 0)
                    }.padding()
                    ForEach(snapshot.game.db.eras, id: \.name) { era in
                        VStack(spacing: 10) {
                            Text(era.name).style("title-3").halign(.start)
                            List(Array(era.packs), id: \.self, selection: nil) { index in
                                LinuxPackRow(index: index, game: snapshot.game, canBuy: model.canBuy(pack: index), buy: { model.buy(pack: index) })
                            }.boxedList()
                        }.padding()
                    }
                }
            }.vexpand()
        }
    }
}

@MainActor private struct LinuxPackRow: View {
    let index: Int
    let game: Game
    let canBuy: Bool
    let buy: () -> Void

    var view: Body {
        let pack = game.db.packs[index]
        let progress = game.progress(index)
        HStack(spacing: 10) {
            VStack(spacing: 10) {
                Text("\(index + 1). \(pack.name)").ellipsize().halign(.start)
                HStack(spacing: 10) {
                    Text("\(progress.owned) / \(progress.total)")
                    if progress.cleared { Text(progress.complete ? "COMPLETE" : "FUSION ONLY").style("dim-label") }
                    if progress.fusionLeft > 0 { Text(L("융합 %lld장 남음", .int(progress.fusionLeft))) }
                }.halign(.start)
                ProgressBar(value: Double(progress.owned), total: Double(max(1, progress.total)))
            }.hexpand()
            Button(coinText(Balance.packPrice), handler: buy)
                .linuxSmokeID("shop-buy-\(index)")
                .insensitive(!canBuy)
        }.padding()
    }
}

@MainActor struct LinuxOpeningView: View {
    let opening: LinuxOpening
    let game: Game
    let close: () -> Void

    static func imageRequest(for pull: Pull, game: Game) -> ImageRequest? {
        game.db.cards[pull.cid]?.imageId.map {
            ImageSource.card(imageID: $0, size: .full, overframe: pull.overframe)
        }
    }

    var view: Body {
        HStack(spacing: 10) {
            Text(opening.freePack ? L("무료 팩 · %@", .text(opening.title)) : opening.title).ellipsize().style("title-3").hexpand().halign(.start)
            Button(L("닫기"), handler: close).linuxSmokeID("opening-close")
        }.padding()
        ScrollView {
            FlowBox(Array(opening.pulls.enumerated()), id: \.offset) { item in
                let pull = item.element
                let card = game.db.cards[pull.cid]
                VStack(spacing: 10) {
                    LinuxPicture(request: Self.imageRequest(for: pull, game: game), size: .grid)
                    .frame(minWidth: 160, minHeight: 234)
                    .frame(maxWidth: 180)
                    Text(card?.name ?? "\(pull.cid)").ellipsize()
                    Text(pull.label)
                    if pull.isNew { Text("NEW").style("success") }
                    if let coins = pull.soldFor { Text(L("자동 판매 +%@", .text(coinText(coins)))) }
                    if pull.overframe { Text(L("오버프레임")) }
                    if pull.bonusPacks > 0 { Text(L("무료 팩 +%lld", .int(pull.bonusPacks))) }
                    if pull.filledCards > 0 { Text(L("팩 완성 보상 %lld", .int(pull.filledCards))) }
                }.padding(6)
            }.homogeneous(true).maxChildrenPerLine(3).padding()
        }.vexpand()
    }
}

extension AnyView {
    /// Native identity for display-backed smoke tests; registered directly on each actual button.
    func linuxSmokeID(_ id: String) -> AnyView {
        inspectOnAppear { storage in
            guard let pointer = storage.opaquePointer else { return }
            gtk_widget_set_name(UnsafeMutablePointer<GtkWidget>(pointer), id)
        }
    }
}
#endif
