import Foundation
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
        #expect(game.progress(0).complete)
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

    @Test func packHasThreeNormalsSlot4MaybeRareAndOneRareSlot() {
        var game = rich()
        var rng = SeededRNG(seed: 11)
        let opened = game.buy(pack: 0, using: &rng)
        #expect(opened.count == 5)
        #expect(opened.prefix(3).allSatisfy { $0.tier == 1 })
        #expect(opened[4].tier >= 2)
        #expect(game.state.coins == 1_000_000 - Balance.packPrice)
        #expect(opened.filter(\.isNew).count == Set(opened.map(\.cid)).count)
        // 4번째 장은 30% 로 레어 (기대 600 / 2,000)
        game.state.coins = 10_000_000
        let rares = (0..<2_000).filter { _ in game.buy(pack: 0, using: &rng)[3].tier == 2 }.count
        #expect((500...700).contains(rares))
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
        #expect(game.progress(2).complete)
        #expect(game.state.coins == 1_000_000 - Balance.packPrice)
    }

    @Test func anyPackBuyableButNotWhenUnaffordable() {
        var rng = SeededRNG(seed: 1)
        var any = rich()
        #expect(!any.buy(pack: 2, using: &rng).isEmpty)  // 해금 없이 아무 팩이나
        var poor = Game(db: db, state: GameState())
        #expect(poor.canAffordPack == false)
        #expect(poor.buy(pack: 0, using: &rng).isEmpty)
        var almost = rich()
        almost.state.coins = Balance.packPrice - 1
        #expect(almost.canAffordPack == false)
        almost.state.coins = Balance.packPrice
        #expect(almost.canAffordPack)
    }

    @Test func lastBoughtPackSkipsFreeCards() {
        var game = rich()
        var rng = SeededRNG(seed: 2)
        #expect(game.lastBoughtPack == 0)
        _ = game.buy(pack: 1, using: &rng)
        game.give(21, source: "free")
        #expect(game.lastBoughtPack == 1)
    }

    @Test func lastBoughtPackIgnoresFreePacksAndLogOverflow() {
        var game = rich()
        var rng = SeededRNG(seed: 2)
        _ = game.buy(pack: 1, using: &rng)
        game.give(21, source: db.packs[0].pid)  // 무료 팩으로 연 팩은 산 팩이 아니다
        #expect(game.lastBoughtPack == 1)
        for _ in 0..<(Balance.logLimit + 5) { game.give(21, source: "free") }  // 팩 기록이 로그에서 밀려나도
        #expect(game.lastBoughtPack == 1)
        game.state.lastBoughtPid = nil  // 필드 없는 옛 세이브는 로그 대체
        game.state.log = [LogEntry(cid: 1, source: db.packs[1].pid, date: Date())]
        #expect(game.lastBoughtPack == 1)
    }

    /// 얻은 카드는 날짜별로 세고, 새 날짜를 셀 때 cardDaysKept 일 지난 날은 지운다
    @Test func giveCountsCardsByDay() {
        var game = rich()
        let fmt = LocalUsageReader.localDayFormatter(), now = Date()
        let old = Calendar.current.date(byAdding: .day, value: -(GameState.cardDaysKept + 1), to: now)!
        game.give(21, source: "free", now: old)
        for _ in 0..<(Balance.logLimit + 5) { game.give(21, source: "free", now: now) }  // 로그 한도와 상관없이 센다
        #expect(game.state.cardsByDay == [fmt.string(from: now): Balance.logLimit + 5])
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

    @Test func freeCardsSkipOwnedCards() {
        // 노멀 50종 중 49종을 가지면 무료 카드는 남은 1종만, 등급 확률은 남은 티어끼리 다시 나눈다
        let big = makeDB([(1...50).map { ($0, 1) } + (51...100).map { ($0, 4) }])
        var state = GameState()
        for cid in 1...49 { state.owned[cid] = 1 }
        let game = Game(db: big, state: state)
        var rng = SeededRNG(seed: 5)
        let draws = (0..<2_000).map { _ in game.drawFree(using: &rng)! }
        #expect(draws.allSatisfy { $0 >= 50 })
        #expect((1_900...1_990).contains(draws.filter { $0 == 50 }.count))  // 기대 1,958 (N:UR = 70:1.5)
    }

    @Test func freeCardsFollowTierWeights() {
        // 노멀 50종 + 울트라(4) 50종: 티어 안 균등이면 울트라 ≈ 2%, 카드 수 비례였다면 ≈ 50%
        let big = makeDB([(1...50).map { ($0, 1) } + (51...100).map { ($0, 4) }])
        let game = Game(db: big, state: GameState())
        var rng = SeededRNG(seed: 5)
        let ultras = (0..<2_000).filter { _ in game.drawFree(using: &rng)! > 50 }.count
        #expect((20...65).contains(ultras))  // 기대 42 (빈 R·SR·SE 를 빼고 N:UR = 70:1.5 로 다시 나눔)
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
        state.owned = [1: 2]
        var game = Game(db: db, state: state)
        #expect(game.sell(1) == Balance.sellPrice[4]! * Balance.clearedSellMultiplier)  // 팩1(카드 1뿐)을 다 모았다
        #expect(game.copies(1) == 1)
        game.state.owned[2] = 1
        game.state.owned[1] = nil  // 이제 카드 2가 든 팩0은 덜 모았다
        #expect(game.sell(2) == Balance.sellPrice[2])
        #expect(game.copies(2) == 0)
        #expect(game.state.owned[2] == nil)
        #expect(game.sell(2) == nil)
        #expect(game.state.coins == Balance.sellPrice[4]! * Balance.clearedSellMultiplier + Balance.sellPrice[2]!)
    }

    @Test func sellingLastFieldBackgroundTurnsItOff() {
        var state = GameState()
        state.owned = [2: 2]
        state.fieldBackground = 2
        var game = Game(db: db, state: state)
        _ = game.sell(2)
        #expect(game.state.fieldBackground == 2)  // 1장 남았다
        _ = game.sell(2)
        #expect(game.state.fieldBackground == nil)
    }

    @Test func sellDuplicatesKeepsOneOfEach() {
        var state = GameState()
        state.owned = [1: 2, 2: 2]
        var game = Game(db: db, state: state)
        let expected = (Balance.sellPrice[4]! + Balance.sellPrice[2]!) * Balance.clearedSellMultiplier  // 두 팩 다 모았다
        #expect(game.duplicatesValue == (2, expected))
        #expect(game.sellDuplicates() == expected)
        #expect(game.state.owned == [1: 1, 2: 1])
        #expect(game.state.coins == expected)
        #expect(game.sellDuplicates() == 0)
    }

    @Test func packResaleValueIsBelowPackPrice() {
        let w = Balance.slot5Weights.reduce(0.0) { $0 + $1.weight * Double(Balance.sellPrice[$1.tier]!) }
        let slot4 = (1 - Balance.slot4RareChance) * Double(Balance.sellPrice[1]!) + Balance.slot4RareChance * Double(Balance.sellPrice[2]!)
        let m = Double(Balance.clearedSellMultiplier)  // 다 모은 팩의 판매가 배수까지 넣어도
        #expect(m * (3.0 * Double(Balance.sellPrice[1]!) + slot4 + w) < Double(Balance.packPrice))
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
        let m = Balance.clearedSellMultiplier  // 첫 봉투로 팩을 다 모아 판매가가 배수가 된다
        #expect(second.compactMap(\.soldFor).sorted() == [Balance.sellPrice[1]! * m, Balance.sellPrice[4]! * m])
        #expect(game.state.owned == [1: 1, 2: 1])
        #expect(game.state.coins == 10_000 - 2 * Balance.packPrice + (Balance.sellPrice[1]! + Balance.sellPrice[4]!) * m)
        // 판매 취소: 코인을 돌려주고 카드가 돌아온다, 코인이 모자라면 거절
        let kept = game.unsell(2, refund: Balance.sellPrice[4]! * m)
        #expect(kept)
        #expect(game.state.owned == [1: 1, 2: 2])
        #expect(game.state.coins == 10_000 - 2 * Balance.packPrice + Balance.sellPrice[1]! * m)
        let short = game.unsell(1, refund: game.state.coins + 1)
        #expect(!short)
        game.state.owned[2] = 1
        game.state.autoSellDuplicates = false
        _ = game.buy(pack: 0, using: &rng)
        #expect(game.state.owned == [1: 2, 2: 2])
    }

    /// 오버프레임 판이 있는 카드는 3장째까지 자동 판매하지 않고, 3장 모으면 해금돼 팔아도 남는다
    @Test func overframeCardKeepsThreeUntilUnlocked() {
        let c = overframeCard("카드1")
        var state = GameState()
        state.autoSellDuplicates = true
        var game = Game(db: oneBoxDB([1: c]), state: state)
        var rng = SeededRNG(seed: 1)
        game.state.pendingFree = 4
        let pulls = game.openFree(using: &rng)
        #expect(pulls.map(\.cid) == [1, 1, 1, 1])
        #expect(pulls.map { $0.soldFor != nil } == [false, false, false, true])
        #expect(pulls.map(\.overframe) == [false, false, true, true])  // 개봉 칸마다 그 장을 받은 직후 그림
        #expect(game.state.owned[1] == 3 && game.showsOverframe(1))
        _ = game.sell(1); _ = game.sell(1)
        #expect(game.showsOverframe(1))  // 팔아도 유지
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

    @Test func potOfGreedGivesTwoFreePacks() {
        let pot = CardDB.potOfGreed
        let db = makeDB([[(pot, 1)]])
        var game = Game(db: db, state: GameState())
        game.state.coins = 1_000_000
        var rng = SeededRNG(seed: 1)
        let pulls = game.buy(pack: 0, using: &rng)
        #expect(pulls.map(\.bonusPacks) == [Balance.potOfGreedFreePacks])
        #expect(game.state.freePacks == Balance.potOfGreedFreePacks)
        game.state.pendingFree = 1
        #expect(game.openFree(using: &rng).first?.bonusPacks == 2)  // 무료 카드에서도
        #expect(game.state.freePacks == 4)
    }

    @Test func exodiaFillsItsPack() {
        let pieces = CardDB.exodia.sorted()
        let base = makeDB([pieces.map { ($0, 4) } + [(1, 1), (2, 5), (3, 4)], [(11, 1)]])
        var cards = base.cards
        cards[3]?.picks = [Pick(any: [1])]  // 융합으로 만들 수 있는 카드는 채우지 않는다
        let db = CardDB(packs: base.packs, cards: cards)
        var game = Game(db: db, state: GameState())
        for c in pieces.dropLast() + [1, 11] { game.state.owned[c] = 1 }
        game.state.pendingFree = 1
        var rng = SeededRNG(seed: 1)
        let pull = game.openFree(using: &rng)[0]  // 남은 건 마지막 조각(UR)·2(SE)·융합 3(UR). 이 시드는 조각
        #expect(pull.cid == pieces.last!)
        #expect(pull.filledCards == 1)
        #expect(game.copies(2) == 1 && game.copies(1) == 1 && game.copies(3) == 0)
    }
}
