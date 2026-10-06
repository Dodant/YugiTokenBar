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
        #expect(game.tierProgress.map(\.total).reduce(0, +) == 11 && game.tierProgress.allSatisfy { $0.owned == 0 })
        #expect(game.db.cards[12] != nil)  // 이름·이미지 조회는 그대로
        var rng = SeededRNG(seed: 3)
        while game.state.pendingFree > 0 { #expect(game.openFree(using: &rng).allSatisfy { $0.cid <= 11 }) }
        while let (pack, _) = game.openFreePack(using: &rng) { #expect(pack < 11) }

        game.state.eraLimit = "GX"
        #expect(game.db.packs.count == 12)
        #expect(game.ownedDistinct == 12)
        #expect(game.tierProgress.map(\.owned).reduce(0, +) == 12)  // 등급별 합 = 보유 종류 수
    }

    @Test func hiddenCardsAreNotSoldOrCounted() {
        var state = GameState()
        state.eraLimit = "DM"
        state.owned = [1: 3, 12: 4]  // 12 = 범위 밖(GX)
        state.favorites = [1, 12]
        state.decks = [Deck(name: "덱", cards: [1: 2, 12: 3])]
        var game = Game(db: db, state: state)
        #expect(game.favoritesInRange == 1)
        let p = game.deckProgress(game.state.decks[0])
        #expect(p.owned == 2 && p.total == 2)
        let dup = game.duplicatesValue  // 카드 1의 2장만 (카드 12의 3장은 숨겨져 있어 제외)
        #expect(dup.count == 2 && dup.coins == 2 * Balance.sellPrice[1]!)
        #expect(game.sellDuplicates() == dup.coins)
        #expect(game.state.owned == [1: 1, 12: 4])
    }
}
