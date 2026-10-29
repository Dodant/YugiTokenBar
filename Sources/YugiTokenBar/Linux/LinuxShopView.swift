#if os(Linux)
import Adwaita
import CAdw
import Foundation

@MainActor struct LinuxShopView: View {
    let snapshot: LinuxSnapshot
    let model: LinuxModel

    var view: Body {
        if let opening = snapshot.opening {
            LinuxOpeningView(opening: opening, game: snapshot.game, close: model.closeOpening, flip: model.flip, flipAll: model.flipAll)
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
    var flip: (Int) -> Void = { _ in }
    var flipAll: () -> Void = {}

    static func imageRequest(for pull: Pull, game: Game) -> ImageRequest? {
        game.db.cards[pull.cid]?.imageId.map {
            ImageSource.card(imageID: $0, size: .full, overframe: pull.overframe)
        }
    }

    var view: Body {
        let _ = LinuxOpeningStyle.install()
        HStack(spacing: 10) {
            Text(opening.freePack ? L("무료 팩 · %@", .text(opening.title)) : opening.title).ellipsize().style("title-3").hexpand().halign(.start)
            if !opening.allFlipped {
                Button(L("모두 뒤집기"), handler: flipAll).linuxSmokeID("opening-flip-all").style("suggested-action")
            }
            Button(L("닫기"), handler: close).linuxSmokeID("opening-close")
        }.padding()
        ScrollView {
            FlowBox(Array(opening.pulls.enumerated()), id: \.offset) { item in
                cell(item.element, item.offset)
            }.homogeneous(true).maxChildrenPerLine(3).padding()
        }.vexpand()
    }

    /// Face down until clicked; the name and badges stay blank until then so nothing leaks early.
    private func cell(_ pull: Pull, _ index: Int) -> AnyView {
        let flipped = opening.flipped.contains(index)
        let card = game.db.cards[pull.cid]
        let front = LinuxPicture(request: Self.imageRequest(for: pull, game: game), size: .grid)
            .overlay { Text("").style("ytb-foil").overlay { Text("").style("ytb-shine") } }
            .style("ytb-front")
        let stack = VStack { front }
            .overlay { LinuxPicture(request: nil, size: .grid).style("ytb-back") }
            .frame(minWidth: 160, minHeight: 234).style("ytb-card")
            .frame(maxWidth: 170).halign(.center).valign(.start)  // a taller row must not enlarge one card
        let extras = [pull.soldFor.map { L("자동 판매 +%@", .text(coinText($0))) }, pull.overframe ? L("오버프레임") : nil,
                      pull.bonusPacks > 0 ? L("무료 팩 +%lld", .int(pull.bonusPacks)) : nil,
                      pull.filledCards > 0 ? L("팩 완성 보상 %lld", .int(pull.filledCards)) : nil].compactMap { $0 }
        return Button("") { flip(index) }.child {
            VStack(spacing: 8) {
                stack
                Text(flipped ? card?.name ?? "\(pull.cid)" : " ").ellipsize().style("ytb-info")
                if flipped {
                    HStack(spacing: 6) {
                        Text(pull.label).style("ytb-rarity").style("ytb-rarity-\(pull.tier)")
                        if pull.isNew { Text("NEW").style("success") }
                        if !extras.isEmpty { Text(extras.joined(separator: " · ")).ellipsize() }
                    }.halign(.center).style("ytb-info")
                } else {
                    Text(" ")
                }
            }.padding(6).frame(maxWidth: 230)
            .style("ytb-tier-\(pull.tier)").style("ytb-flipped", active: flipped).style("ytb-late", active: flipped && opening.lateFlip == index)
        }.linuxSmokeID("opening-card-\(index)").style("flat")
    }
}

/// Pack-opening motion in GTK CSS, after PackOpenView.swift: the back folds away, the face unfolds, and SR or better
/// adds a flash, one diagonal shine, a short pop and a breathing glow (UR+: slow rainbow foil). Only 2D transforms,
/// so the cairo renderer draws it too; with animations off in GNOME, the final state shows at once.
/// Colours mirror Rarity.colors / Rarity.pillColors in CardImageView.swift.
@MainActor enum LinuxOpeningStyle {
    private static var installed = false
    static func install() {
        guard !installed, let display = gdk_display_get_default() else { return }
        installed = true
        let provider = gtk_css_provider_new()
        gtk_css_provider_load_from_string(provider, css)
        gtk_style_context_add_provider_for_display(display, OpaquePointer(provider), UInt32(GTK_STYLE_PROVIDER_PRIORITY_APPLICATION))
        g_object_unref(provider)
    }

    static let colors = ["#8E96A3", "#4A90E2", "#F5C451", "#B05CFF", "#FF3D7F"]
    static let pills = ["#5C6470", "#2F6DB5", "#F5C451", "#8A3FD6", "#D21E5F"]

    static var css: String {
        var css = """
        @keyframes ytb-fold { from { opacity: 1; transform: scale(1, 1); } to { opacity: 1; transform: scale(0.02, 1); } }
        @keyframes ytb-unfold { from { opacity: 1; transform: scale(0.02, 1); } to { opacity: 1; transform: scale(1, 1); } }
        @keyframes ytb-sweep { from { background-position: 100% 100%; } to { background-position: 0% 0%; } }
        @keyframes ytb-foil { from { background-position: 0% 50%; } to { background-position: 100% 50%; } }
        @keyframes ytb-fade { from { opacity: 0; } to { opacity: 1; } }
        @keyframes ytb-foil-in { from { opacity: 0; } to { opacity: 0.1; } }
        .ytb-card, .ytb-front, .ytb-back, .ytb-foil, .ytb-shine { border-radius: 7px; }
        .ytb-front { opacity: 0; }
        .ytb-flipped .ytb-front { opacity: 1; animation: ytb-unfold 200ms ease-out 200ms backwards; }
        .ytb-flipped .ytb-back { opacity: 0; animation: ytb-fold 200ms ease-in backwards; }
        .ytb-flipped.ytb-late .ytb-front { animation-delay: 800ms; }
        .ytb-flipped.ytb-late .ytb-back { animation-delay: 600ms; }
        .ytb-flipped.ytb-late .ytb-info { animation-delay: 900ms; }
        .ytb-flipped .ytb-info { animation: ytb-fade 300ms ease-out 300ms backwards; }
        .ytb-shine { background-repeat: no-repeat; background-size: 400% 400%; background-position: 100% 100%; }
        .ytb-foil { opacity: 0; background-size: 300% 100%; }
        .ytb-rarity { border-radius: 999px; padding: 0 7px; font-size: smaller; font-weight: bold; color: white; }
        .ytb-tier-3 .ytb-rarity { color: black; }

        """
        for tier in 1...5 {
            let color = colors[tier - 1]
            css += ".ytb-rarity-\(tier) { background-color: \(pills[tier - 1]); }\n"
            guard tier >= 2 else { continue }
            css += ".ytb-tier-\(tier) .ytb-back { box-shadow: 0 0 10px 1px alpha(\(color), 0.9); }\n"
            guard tier >= 3 else {
                css += ".ytb-flipped.ytb-tier-\(tier) .ytb-front { box-shadow: 0 0 10px 1px alpha(\(color), 0.9); }\n"
                continue
            }
            let ur = tier >= 4, se = tier >= 5
            let peak = se ? 1.09 : ur ? 1.06 : 1.035, flash = se ? 0.35 : ur ? 0.28 : 0.2
            let sweep = se ? 1900 : ur ? 1700 : 1500
            let tint = se ? "rgba(255,230,180,0.6)" : "rgba(255,255,255,0.62)"
            let edge = ur && !se ? ("alpha(cyan,0.12)", "alpha(pink,0.12)") : ("alpha(white,0.1)", "alpha(white,0.1)")
            let halo = se ? ", 0 0 12px 2px alpha(#FFCC40, 0.25)" : ""
            let haloPeak = se ? ", 0 0 24px 6px alpha(#FFCC40, 0.7)" : ""
            css += """
            @keyframes ytb-pop-\(tier) { 0% { transform: scale(1); } 30% { transform: scale(\(peak)); } 100% { transform: scale(1); } }
            @keyframes ytb-glow-\(tier) { from { box-shadow: 0 0 9px 1px alpha(\(color), 0.4)\(halo); } to { box-shadow: 0 0 16px 4px alpha(\(color), 0.8)\(haloPeak); } }
            @keyframes ytb-flash-\(tier) { 0% { background-color: alpha(white, 0); } 10% { background-color: alpha(white, \(flash)); } 100% { background-color: alpha(white, 0); } }
            .ytb-flipped.ytb-tier-\(tier) .ytb-card { animation: ytb-pop-\(tier) 1000ms ease-out 300ms; }
            .ytb-flipped.ytb-tier-\(tier) .ytb-front { box-shadow: 0 0 12px 2px alpha(\(color), 0.7)\(halo);
                animation: ytb-unfold 200ms ease-out 200ms backwards, ytb-glow-\(tier) 2200ms ease-in-out 350ms infinite alternate; }
            .ytb-tier-\(tier) .ytb-shine { background-image: linear-gradient(135deg, transparent 44%, \(edge.0) 46.5%, \(tint) 49%,
                alpha(white, 0.62) 50%, \(tint) 51%, \(edge.1) 53.5%, transparent 56%); }
            .ytb-flipped.ytb-tier-\(tier) .ytb-shine { animation: ytb-flash-\(tier) 700ms linear 320ms, ytb-sweep \(sweep)ms ease-in-out 400ms; }
            .ytb-flipped.ytb-late.ytb-tier-\(tier) .ytb-card { animation-delay: 900ms; }
            .ytb-flipped.ytb-late.ytb-tier-\(tier) .ytb-front { animation-delay: 800ms, 950ms; }
            .ytb-flipped.ytb-late.ytb-tier-\(tier) .ytb-shine { animation-delay: 920ms, 1000ms; }

            """
            if ur {
                let foil = se ? "#FFCC40, orange, pink, white, #FFCC40" : "red, orange, yellow, lime, cyan, blue, purple, red"
                css += """
                .ytb-tier-\(tier) .ytb-foil { background-image: linear-gradient(120deg, \(foil)); }
                .ytb-flipped.ytb-tier-\(tier) .ytb-foil { opacity: 0.1; animation: ytb-foil-in 400ms 350ms backwards, ytb-foil 10s linear 350ms infinite alternate; }

                """
            }
        }
        return css
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
