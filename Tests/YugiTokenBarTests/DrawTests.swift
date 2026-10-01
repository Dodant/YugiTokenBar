import Testing
@testable import YugiTokenBar

@Suite struct DrawTests {
    /// 팩0: 노멀 4 + 레어 1 + 울트라 1, 팩1: 노멀 4, 팩2: 노멀 2
    let db = makeDB([
        [(1, 1), (2, 1), (3, 1), (4, 1), (5, 2), (6, 4)],
        [(11, 1), (12, 1), (13, 1), (14, 1)],
        [(21, 1), (22, 1)],
    ])

    func rich(_ owned: [Int: Int] = [:]) -> Game {
        var state = GameState()
        state.coins = 1_000_000
        state.owned = owned
        return Game(db: db, state: state)
    }

    @Test func neverGivesThirdCopy() {
        var game = rich()
        var rng = SeededRNG(seed: 7)
        for _ in 0..<50 { _ = game.buy(pack: 0, using: &rng) }
        #expect(game.state.owned.values.allSatisfy { $0 <= Balance.maxCopies })
        #expect(game.isComplete(0))
    }

    @Test func emptyTierFallsDownThenUp() {
        var rng = SeededRNG(seed: 3)
        // 레어(2) 전부 2장 → 노멀로 내려감
        let down = rich([5: 2])
        #expect(down.draw(pack: 0, tier: 2, using: &rng)?.tier == 1)
        // 노멀·레어 전부 2장 → 위로 올라가 울트라
        let up = rich([1: 2, 2: 2, 3: 2, 4: 2, 5: 2])
        #expect(up.draw(pack: 0, tier: 2, using: &rng)?.cid == 6)
        // 최상위 티어 요청도 범위 밖 크래시 없이 아래로
        #expect(rich().draw(pack: 0, tier: 5, using: &rng)?.cid == 6)
    }

    @Test func packHasFourNormalsAndOneRareSlot() {
        var game = rich()
        var rng = SeededRNG(seed: 11)
        let opened = game.buy(pack: 0, using: &rng)
        #expect(opened.count == 5)
        #expect(opened.prefix(4).allSatisfy { $0.tier == 1 })
        #expect(opened[4].tier >= 2)
        #expect(game.state.coins == 1_000_000 - Balance.packPrice)
        #expect(opened.filter(\.isNew).count == Set(opened.map(\.cid)).count)
    }

    @Test func noDuplicateCardWithinOnePack() {
        var game = rich()
        var rng = SeededRNG(seed: 1)
        for _ in 0..<5 {
            let pulls = game.buy(pack: 0, using: &rng)
            #expect(Set(pulls.map(\.cid)).count == pulls.count)
        }
    }

    @Test func completedPackCannotBeBought() {
        // 팩2는 2종 × 2장 = 4장이면 완료. 한 팩에 같은 카드가 안 나오므로 팩당 2장 → 2팩이면 완료
        var game = rich()
        var rng = SeededRNG(seed: 5)
        #expect(game.buy(pack: 2, using: &rng).count == 2)
        #expect(game.buy(pack: 2, using: &rng).count == 2)
        #expect(game.isComplete(2))
        #expect(game.canBuy(2) == false)
        #expect(game.buy(pack: 2, using: &rng).isEmpty)
        #expect(game.state.coins == 1_000_000 - Balance.packPrice * 2)
    }

    @Test func anyPackBuyableButNotWhenUnaffordable() {
        var rng = SeededRNG(seed: 1)
        var any = rich()
        #expect(!any.buy(pack: 2, using: &rng).isEmpty)  // 해금 없이 아무 팩이나
        var poor = Game(db: db, state: GameState())
        #expect(poor.canBuy(0) == false)
        #expect(poor.buy(pack: 0, using: &rng).isEmpty)
        var almost = rich()
        almost.state.coins = Balance.packPrice - 1
        #expect(almost.canBuy(0) == false)
        almost.state.coins = Balance.packPrice
        #expect(almost.canBuy(0))
    }

    @Test func lastBoughtPackSkipsFreeCards() {
        var game = rich()
        var rng = SeededRNG(seed: 2)
        #expect(game.lastBoughtPack == 0)
        _ = game.buy(pack: 1, using: &rng)
        game.give(21, source: "free")
        #expect(game.lastBoughtPack == 1)
    }

    @Test func freeCardsComeFromWholePoolAndRespectCap() {
        var game = rich()
        var rng = SeededRNG(seed: 9)
        var seenPacks = Set<Int>()
        for _ in 0..<12 {
            let cid = game.drawFree(using: &rng)!
            game.give(cid, source: "free")
            seenPacks.insert(cid / 10)
        }
        #expect(seenPacks.count > 1)  // 모든 팩에서 나온다
        #expect(game.state.owned.values.allSatisfy { $0 <= 2 })
        let full = rich(Dictionary(uniqueKeysWithValues: db.allCIDs.map { ($0, 2) }))
        #expect(full.drawFree(using: &rng) == nil)
    }

    @Test func logKeepsNewestFifty() {
        var game = rich()
        for i in 0..<60 { game.give(1 + i % 6, source: "test") }
        #expect(game.state.log.count == Balance.logLimit)
    }
}

@Suite struct SellTests {
    /// 카드 1: 팩0 노멀 / 팩1 울트라 재수록, 카드 2: 팩0 레어
    let db = makeDB([[(1, 1), (2, 2)], [(1, 4)]])

    @Test func sellGivesCoinsByHighestTierAndRemovesCopy() {
        var state = GameState()
        state.owned = [1: 2, 2: 1]
        var game = Game(db: db, state: state)
        #expect(game.sell(1) == Balance.sellPrice[4])
        #expect(game.copies(1) == 1)
        #expect(game.sell(2) == Balance.sellPrice[2])
        #expect(game.copies(2) == 0)
        #expect(game.state.owned[2] == nil)
        #expect(game.sell(2) == nil)
        #expect(game.state.coins == Balance.sellPrice[4]! + Balance.sellPrice[2]!)
    }

    @Test func sellDuplicatesKeepsOneOfEach() {
        var state = GameState()
        state.owned = [1: 2, 2: 2]
        var game = Game(db: db, state: state)
        let expected = Balance.sellPrice[4]! + Balance.sellPrice[2]!
        #expect(game.duplicatesValue == (2, expected))
        #expect(game.sellDuplicates() == expected)
        #expect(game.state.owned == [1: 1, 2: 1])
        #expect(game.state.coins == expected)
        #expect(game.sellDuplicates() == 0)
    }

    @Test func packResaleValueIsBelowPackPrice() {
        let w = Balance.slot5Weights.reduce(0.0) { $0 + $1.weight * Double(Balance.sellPrice[$1.tier]!) }
        #expect(4.0 * Double(Balance.sellPrice[1]!) + w < Double(Balance.packPrice))
    }
}
