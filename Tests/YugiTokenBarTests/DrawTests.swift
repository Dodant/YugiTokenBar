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

    @Test func noCopyCapAndCompletePackStillBuyable() {
        var game = rich()
        var rng = SeededRNG(seed: 7)
        for _ in 0..<50 { _ = game.buy(pack: 0, using: &rng) }
        #expect(game.state.owned.values.contains { $0 > 2 })  // 상한 없음
        #expect(game.isComplete(0))
        #expect(game.buy(pack: 0, using: &rng).count == 5)  // 완료 팩도 계속 산다
    }

    @Test func emptyTierFallsDownThenUp() {
        var rng = SeededRNG(seed: 3)
        // 팩0에 SR(3) 없음 → 아래로 내려가 레어
        #expect(rich().draw(pack: 0, tier: 3, using: &rng) == 5)
        // 노멀·레어가 이미 봉투에 나왔으면 → 위로 올라가 울트라
        #expect(rich().draw(pack: 0, tier: 2, excluding: [1, 2, 3, 4, 5], using: &rng) == 6)
        // SE 가 없는 팩이면 아래(UR)로
        #expect(rich().draw(pack: 0, tier: 5, using: &rng) == 6)
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

    @Test func smallPackGivesEachCardOnce() {
        // 팩2는 2종뿐 → 한 봉투에 같은 카드가 안 나오므로 2장, 한 번에 완료
        var game = rich()
        var rng = SeededRNG(seed: 5)
        #expect(game.buy(pack: 2, using: &rng).count == 2)
        #expect(game.isComplete(2))
        #expect(game.state.coins == 1_000_000 - Balance.packPrice)
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

    @Test func freeCardsComeFromWholePool() {
        var game = rich()
        var rng = SeededRNG(seed: 9)
        var seenPacks = Set<Int>()
        for _ in 0..<12 {
            let cid = game.drawFree(using: &rng)!
            game.give(cid, source: "free")
            seenPacks.insert(cid / 10)
        }
        #expect(seenPacks.count > 1)  // 모든 팩에서 나온다
        let full = rich(Dictionary(uniqueKeysWithValues: db.allCIDs.map { ($0, 2) }))
        #expect(full.drawFree(using: &rng) != nil)  // 다 가져도 계속 나온다
    }

    @Test func freeCardsFollowTierWeights() {
        // 노멀 50종 + 울트라(4) 50종: 티어 안 균등이면 울트라 ≈ 2%, 카드 수 비례였다면 ≈ 50%
        let big = makeDB([(1...50).map { ($0, 1) } + (51...100).map { ($0, 4) }])
        let game = Game(db: big, state: GameState())
        var rng = SeededRNG(seed: 5)
        let ultras = (0..<2_000).filter { _ in game.drawFree(using: &rng)! > 50 }.count
        #expect((20...65).contains(ultras))  // 기대 40 (N 70% + 빈 R·SR 28% → N 으로 내려감, 빈 SE 0.5% → UR, UR 2%)
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

    @Test func autoSellDuplicatesSellsRepeatsOnly() {
        // 2종뿐인 팩: 한 봉투에 2장 → 두 번째 봉투부터 둘 다 중복
        let db = makeDB([[(1, 1), (2, 4)]])
        var state = GameState()
        state.coins = 10_000
        state.autoSellDuplicates = true
        var game = Game(db: db, state: state)
        var rng = SeededRNG(seed: 1)
        let first = game.buy(pack: 0, using: &rng)
        #expect(first.allSatisfy { $0.isNew && $0.soldFor == nil })
        let second = game.buy(pack: 0, using: &rng)
        #expect(second.compactMap(\.soldFor).sorted() == [Balance.sellPrice[1]!, Balance.sellPrice[4]!])
        #expect(game.state.owned == [1: 1, 2: 1])
        #expect(game.state.coins == 10_000 - 2 * Balance.packPrice + Balance.sellPrice[1]! + Balance.sellPrice[4]!)
        game.state.autoSellDuplicates = false
        _ = game.buy(pack: 0, using: &rng)
        #expect(game.state.owned == [1: 2, 2: 2])
    }

    @Test func everyTenPaidPacksGiveOneFreePack() {
        let db = makeDB([[(1, 1), (2, 1), (3, 1), (4, 1), (5, 2)], [(11, 1), (12, 1), (13, 1), (14, 1)]])
        var game = Game(db: db, state: GameState())
        game.state.coins = 1_000_000
        var rng = SeededRNG(seed: 4)
        for _ in 0..<9 { _ = game.buy(pack: 0, using: &rng) }
        #expect(game.state.packStamp == 9)
        #expect(game.state.freePacks == 0)
        _ = game.buy(pack: 0, using: &rng)
        #expect(game.state.packStamp == 0)
        #expect(game.state.freePacks == 1)
        let coins = game.state.coins
        let free = game.openFreePack(using: &rng)
        #expect(free != nil && !free!.pulls.isEmpty)  // 랜덤 부스터 1팩
        #expect(game.state.coins == coins)
        #expect(game.state.freePacks == 0)
        #expect(game.state.packStamp == 0)  // 무료로 깐 건 세지 않는다
        #expect(game.openFreePack(using: &rng) == nil)
        // 여러 번 열면 여러 팩에서 나온다
        game.state.freePacks = 20
        let packs = Set((0..<20).compactMap { _ in game.openFreePack(using: &rng)?.pack })
        #expect(packs.count == 2)
    }
}
