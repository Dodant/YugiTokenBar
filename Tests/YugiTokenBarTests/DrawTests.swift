import Testing
@testable import YugiTokenBar

@Suite struct DrawTests {
    /// 팩0: 노멀 4 + 레어 1 + 울트라 1, 팩1: 노멀 4, 팩2: 노멀 2
    let db = makeDB([
        [(1, 1), (2, 1), (3, 1), (4, 1), (5, 2), (6, 4)],
        [(11, 1), (12, 1), (13, 1), (14, 1)],
        [(21, 1), (22, 1)],
    ])

    func rich(_ owned: [Int: Int] = [:], unlocked: Int = 1) -> Game {
        var state = GameState()
        state.coins = 1_000_000
        state.owned = owned
        state.unlocked = unlocked
        return Game(db: db, state: state)
    }

    @Test func neverGivesThirdCopy() {
        var game = rich()
        var rng = SeededRNG(seed: 7)
        for _ in 0..<50 { _ = game.buy(pack: 0, count: 1, using: &rng) }
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
        let opened = game.buy(pack: 0, count: 1, using: &rng)
        #expect(opened.count == 1)
        #expect(opened[0].count == 5)
        #expect(opened[0].prefix(4).allSatisfy { $0.tier == 1 })
        #expect(opened[0][4].tier >= 2)
        #expect(game.state.coins == 1_000_000 - Balance.packPrice)
        #expect(opened[0].filter(\.isNew).count == Set(opened[0].map(\.cid)).count)
    }

    @Test func noDuplicateCardWithinOnePack() {
        var game = rich()
        var rng = SeededRNG(seed: 1)
        for _ in 0..<5 {
            for pulls in game.buy(pack: 0, count: 1, using: &rng) {
                #expect(Set(pulls.map(\.cid)).count == pulls.count)
            }
        }
    }

    @Test func multiBuyStopsWhenPackCompletesAndKeepsCoins() {
        // 팩2는 2종 × 2장 = 4장이면 완료. 한 팩에 같은 카드가 안 나오므로 팩당 2장 → 5팩 사도 2팩만 열림
        var game = rich(unlocked: 3)
        var rng = SeededRNG(seed: 5)
        let opened = game.buy(pack: 2, count: 5, using: &rng)
        #expect(opened.count == 2)
        #expect(game.isComplete(2))
        #expect(game.state.coins == 1_000_000 - Balance.packPrice * 2)
        #expect(game.canBuy(2) == false)
        #expect(game.buy(pack: 2, count: 1, using: &rng).isEmpty)
    }

    @Test func cannotBuyLockedOrUnaffordable() {
        var rng = SeededRNG(seed: 1)
        var locked = rich()
        #expect(locked.buy(pack: 1, count: 1, using: &rng).isEmpty)
        var poor = Game(db: db, state: GameState())
        #expect(poor.canBuy(0) == false)
        #expect(poor.buy(pack: 0, count: 1, using: &rng).isEmpty)
        var almost = rich()
        almost.state.coins = Balance.packPrice * 4
        #expect(almost.canBuy(0, count: 5) == false)
        #expect(almost.canBuy(0, count: 4))
    }

    @Test func unlockAtExactlyHalfAndChains() {
        var game = rich()
        game.give(1, source: "test")
        game.give(2, source: "test")
        #expect(game.state.unlocked == 1)  // 2/6
        game.give(3, source: "test")
        #expect(game.state.unlocked == 2)  // 3/6 = 50%
        // 잠긴 팩1 을 무료 카드로 미리 50% 채워두면 팩0 해금 순간 연쇄로 열린다
        var chain = rich([11: 1, 12: 1])
        chain.give(1, source: "free")
        chain.give(2, source: "free")
        chain.give(3, source: "free")
        #expect(chain.state.unlocked == 3)
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
        #expect(seenPacks.count > 1)  // 잠긴 팩 카드도 나온다
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
