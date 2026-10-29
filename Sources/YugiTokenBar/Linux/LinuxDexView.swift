#if os(Linux)
import Adwaita
import Foundation

@MainActor struct LinuxDexView: View {
    let snapshot: LinuxSnapshot
    let model: LinuxModel
    @State private var confirmSell = false

    static func imageRequest(for cid: Int, game: Game) -> ImageRequest? {
        game.db.cards[cid]?.imageId.map { ImageSource.card(imageID: $0, size: .full, overframe: game.showsOverframe(cid)) }
    }

    var view: Body {
        let game = snapshot.game
        let duplicates = game.duplicatesValue
        VStack {
            if let pack = snapshot.dexPack, game.db.packs.indices.contains(pack) {
                LinuxDexGrid(pack: pack, game: game, select: model.selectDexCard, back: { model.selectDexPack(nil) })
            } else {
                LinuxDexPacks(game: game, duplicates: duplicates, select: model.selectDexPack, sell: { confirmSell = true })
            }
        }
        .vexpand()
        .dialog(visible: Binding(get: { snapshot.dexCard != nil }, set: { if !$0 { model.selectDexCard(nil) } }),
                title: snapshot.dexCard.flatMap { game.db.cards[$0]?.name }, id: "card", width: 460, height: 640) {
            LinuxCardContent(cid: snapshot.dexCard, game: game, sell: { model.sell($0) })
        }
        .dialog(visible: $confirmSell, title: L("중복 판매"), id: "bulk", width: 380) {
            VStack(spacing: 10) {
                Text(L("중복 카드 %lld장을 +%@에 팔까요?", .int(duplicates.count), .text(coinText(duplicates.coins)))).wrap().padding()
                HStack(spacing: 10) {
                    Button(L("취소")) { confirmSell = false }.linuxSmokeID("dex-sell-duplicates-cancel")
                    Button(L("판매")) { confirmSell = false; model.sellDuplicates() }
                        .linuxSmokeID("dex-sell-duplicates-confirm").style("destructive-action")
                }.padding()
            }
        }
    }
}

@MainActor private struct LinuxDexPacks: View {
    let game: Game
    let duplicates: (count: Int, coins: Int)
    let select: (Int?) -> Void
    let sell: () -> Void

    var view: Body {
        HStack(spacing: 10) {
            Text(L("전체 %lld / %lld", .int(game.ownedDistinct), .int(game.db.allCIDs.count))).style("title-3").hexpand().halign(.start)
            Button(L("중복 판매 · %lld장 · +%@", .int(duplicates.count), .text(coinText(duplicates.coins))), handler: sell)
                .linuxSmokeID("dex-sell-duplicates")
                .insensitive(duplicates.count == 0)
        }.padding()
        ScrollView {
            VStack(spacing: 10) {
                ForEach(game.db.eras, id: \.name) { era in
                    let progress = game.progress(packs: era.packs)
                    VStack(spacing: 10) {
                        HStack(spacing: 10) {
                            Text(era.name).style("title-3").hexpand().halign(.start)
                            Text("\(progress.owned) / \(progress.total)").style("dim-label")
                        }
                        List(Array(era.packs), id: \.self, selection: nil) { index in
                            let pack = game.db.packs[index]
                            let progress = game.progress(index)
                            Button("") { select(index) }.child {
                                VStack(spacing: 6) {
                                    Text("\(index + 1). \(pack.name)").ellipsize().halign(.start)
                                    HStack(spacing: 10) {
                                        if pack.kind == .duelist { Text("DP").style("caption-heading") }
                                        Text("\(progress.owned) / \(progress.total)")
                                        if progress.cleared { Text(progress.complete ? "COMPLETE" : "FUSION ONLY").style("dim-label") }
                                    }.halign(.start)
                                    ProgressBar(value: Double(progress.owned), total: Double(max(1, progress.total)))
                                }.padding()
                            }.linuxSmokeID("dex-pack-\(index)").style("flat")
                        }.boxedList()
                    }.padding()
                }
            }
        }.vexpand()
    }
}

@MainActor private struct LinuxDexGrid: View {
    let pack: Int
    let game: Game
    let select: (Int?) -> Void
    let back: () -> Void

    var view: Body {
        let info = game.db.packs[pack]
        let progress = game.progress(pack)
        HStack(spacing: 10) {
            Button(L("뒤로"), handler: back).linuxSmokeID("dex-back")
            VStack(spacing: 4) {
                Text("\(pack + 1). \(info.name)").ellipsize().style("title-3").halign(.start)
                Text("\(progress.owned) / \(progress.total)").style("dim-label").halign(.start)
            }.hexpand()
        }.padding()
        ScrollView {
            FlowBox(info.cards, id: \.self) { cid in
                let copies = game.copies(cid)
                Button("") { select(cid) }.child {
                    VStack(spacing: 6) {
                        if copies > 0 {
                            LinuxPicture(request: LinuxDexView.imageRequest(for: cid, game: game), size: .grid)
                                .frame(minWidth: 130, minHeight: 190)
                        } else {
                            LinuxPicture(request: nil, size: .grid)
                                .frame(minWidth: 130, minHeight: 190).style("dim-label")
                        }
                        Text(game.db.cards[cid]?.name ?? "\(cid)").ellipsize()
                        // Every cell keeps the same lines so the homogeneous grid gives every picture the same size.
                        Text(copies > 1 ? L("보유 %lld장", .int(copies)) : " ")
                    }.padding(4).frame(maxWidth: 150)  // long names ellipsize instead of widening every column
                }.linuxSmokeID("dex-card-\(cid)").style("flat")
            }.homogeneous(true).maxChildrenPerLine(4).padding()
        }.vexpand()
    }
}
#endif
