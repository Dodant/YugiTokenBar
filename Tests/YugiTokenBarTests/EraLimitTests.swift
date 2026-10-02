import Testing
@testable import YugiTokenBar

@Suite struct EraLimitTests {
    // 팩 12개 → DM 0..<11, GX 11..<12. 팩마다 고유 카드 1장 (cid = 팩 번호 + 1)
    let db = makeDB((0..<12).map { [($0 + 1, 1)] })

    @Test func eraLimitNarrowsPacksCardsAndDraws() {
        var state = GameState()
        #expect(state.eraLimit == "GX")  // 기본값
        state.eraLimit = "DM"
        state.owned = [12: 1]  // 범위 밖(GX) 카드는 세지 않는다
        state.pendingFree = 50
        state.freePacks = 20
        var game = Game(db: db, state: state)
        #expect(game.db.packs.count == 11)
        #expect(game.db.allCIDs == Array(1...11))
        #expect(game.db.eras.map(\.name) == ["DM"])
        #expect(game.ownedDistinct == 0)
        #expect(game.db.cards[12] != nil)  // 이름·이미지 조회는 그대로
        var rng = SeededRNG(seed: 3)
        while game.state.pendingFree > 0 { #expect(game.openFree(using: &rng).allSatisfy { $0.cid <= 11 }) }
        while let (pack, _) = game.openFreePack(using: &rng) { #expect(pack < 11) }

        game.state.eraLimit = "GX"
        #expect(game.db.packs.count == 12)
        #expect(game.ownedDistinct == 12)
    }
}
