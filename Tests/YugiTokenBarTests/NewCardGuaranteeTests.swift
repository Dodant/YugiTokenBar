import Testing
@testable import YugiTokenBar

@Suite struct NewCardGuaranteeTests {
    /// 팩에 미보유 카드가 남아 있는 동안은 봉투마다 새 카드가 1장 이상, 다 모은 뒤엔 그냥 5장.
    @Test func everyPackHasANewCardUntilComplete() {
        let list = (1...12).map { ($0, 1) } + (13...16).map { ($0, 2) } + [(17, 3), (18, 4), (19, 5)]
        let db = makeDB([list.map { (cid: $0.0, tier: $0.1) }])
        var rng = SeededRNG(seed: 3)
        var game = Game(db: db, state: GameState())
        for _ in 0..<60 {
            let complete = db.packs[0].cards.allSatisfy { game.copies($0) > 0 }
            game.state.coins = Balance.packPrice
            let pulls = game.buy(pack: 0, using: &rng)
            #expect(pulls.count == 5)
            if !complete { #expect(pulls.contains { $0.isNew }) }
        }
        #expect(db.packs[0].cards.allSatisfy { game.copies($0) > 0 })
    }

    /// 남은 미보유가 SE 한 장뿐이면 그 SE 가 나온다.
    @Test func lastUnownedRareStillComes() {
        let db = makeDB([(1...10).map { (cid: $0, tier: 1) } + [(cid: 11, tier: 2), (cid: 12, tier: 5)]])
        var rng = SeededRNG(seed: 9)
        for _ in 0..<50 {
            var game = Game(db: db, state: GameState())
            for cid in 1...11 { game.state.owned[cid] = 1 }
            game.state.coins = Balance.packPrice
            #expect(game.buy(pack: 0, using: &rng).contains { $0.cid == 12 && $0.isNew })
        }
    }
}
