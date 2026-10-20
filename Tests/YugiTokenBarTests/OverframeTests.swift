#if os(macOS)
import Foundation
import Testing
@testable import YugiTokenBar

/// 오버프레임 해금: 3장 모으면 해금, 팔아도 유지, 해금 전엔 판매·융합 소재로 쓰지 않는다
@Suite struct OverframeTests {
    @Test func lockedCardKeepsAllCopiesInManualSell() {
        var game = Game(db: oneBoxDB([1: overframeCard("카드1")]), state: GameState())
        game.state.owned[1] = 2
        #expect(game.keep(1) == 3 && game.duplicatesValue.count == 0 && game.sellDuplicates() == 0)
        #expect(game.keep(1) == 3)
        game.state.overframes = [1]
        #expect(game.keep(1) == 1 && game.duplicatesValue.count == 1)
    }

    @Test func progressCountsOnlyOverframeCards() {
        var game = Game(db: oneBoxDB([1: overframeCard("카드1"), 2: card("카드2")]), state: GameState())
        #expect(game.overframeProgress == (0, 1))
        game.state.owned = [1: 3, 2: 3]
        game.unlockOwnedOverframes()
        #expect(game.overframeProgress == (1, 1) && game.state.overframes == [1])  // 그림이 없는 카드는 해금하지 않는다
    }

    @Test func unsellToThreeUnlocks() {
        var game = Game(db: oneBoxDB([1: overframeCard("카드1")]), state: GameState())
        game.state.owned[1] = 2
        let kept = game.unsell(1, refund: 0)
        #expect(kept && game.showsOverframe(1))
    }

    /// 해금 전 오버프레임 카드는 조건 소재로 고르지 않고, 그 카드뿐이면 융합할 수 없다
    @Test func lockedCardIsNotUsedAsMaterial() {
        var fusion = card("융합 용", type: "드래곤족/융합", tier: 4)
        fusion.materials = [Material(rule: "드래곤족 몬스터")]
        fusion.picks = [Pick(any: [1, 2])]
        let db = oneBoxDB([1: overframeCard("용 1", type: "드래곤족"), 2: card("용 2", type: "드래곤족"), 20: fusion,
                           CardDB.fusionSpell: card("융합", attr: "마법", type: "일반", kind: "spell")])
        var game = Game(db: db, state: GameState())
        game.state.owned = [1: 2, 2: 1, CardDB.fusionSpell: 1]
        #expect(game.pickMaterials(20) == [[2: 1]])  // 장 수가 더 많아도 해금 전이면 건너뛴다
        game.state.owned[2] = nil
        #expect(game.pickMaterials(20) == nil && !game.canFuse(20))
        game.state.overframes = [1]
        #expect(game.pickMaterials(20) == [[1: 1]])
    }

    /// 다 모은 팩에선 아직 필요한 카드(해금 전 오버프레임)가 같은 등급 안에서 `wantedWeight` 배 잘 나오고, 상점은 그 팩을 막지 않는다
    @Test func clearedPackBoostsWantedCards() {
        var cards: [Int: CardInfo] = [1: overframeCard("카드1")]
        for cid in 2...10 { cards[cid] = card("카드\(cid)") }
        var game = Game(db: oneBoxDB(cards), state: GameState())
        game.state.owned = Dictionary(uniqueKeysWithValues: (1...10).map { ($0, 1) })
        let p = game.progress(0)
        #expect(p.cleared && p.wanted == 1 && !p.done)
        var rng = SeededRNG(seed: 7)
        let boosted = (0..<1_000).filter { _ in game.draw(pack: 0, tier: 1, boostWanted: true, using: &rng) == 1 }.count
        let plain = (0..<1_000).filter { _ in game.draw(pack: 0, tier: 1, using: &rng) == 1 }.count
        #expect(boosted > 450 && plain < 160)  // 기대값 10/19 ≈ 526, 1/10 = 100
        game.state.overframes = [1]
        #expect(game.progress(0).done)
    }

    /// 다 모은 팩의 5번째 장은 `wantedSlotChance`로 등급과 상관없이 필요한 카드가 된다 (UR 소재도 구할 수 있게)
    @Test func clearedPackSlotFiveFavorsWantedCard() {
        var cards: [Int: CardInfo] = [1: CardInfo(name: "UR", attr: nil, level: nil, type: nil, atk: nil, def: nil, text: "",
                                                  imageId: ImageSource.overframe.keys.sorted()[0], tier: 4, kindCode: nil)]
        for cid in 2...11 { cards[cid] = card("카드\(cid)") }
        var game = Game(db: oneBoxDB(cards), state: GameState())
        var rng = SeededRNG(seed: 3)
        let hits = (0..<1_000).filter { _ in
            game.state.owned = Dictionary(uniqueKeysWithValues: (1...11).map { ($0, 1) })
            game.state.coins = Balance.packPrice
            return game.buy(pack: 0, using: &rng).contains { $0.cid == 1 }
        }.count
        #expect(hits > 320)  // 기대값 0.30 + 0.70 × 0.12(UR·SE 칸) ≈ 384, 보장이 없으면 120
    }

    @MainActor @Test func unlocksOwnedCardsOnLaunch() throws {
        let (model, store) = try makeModel(oneBoxDB([1: overframeCard("카드1")])) { $0.owned[1] = 3 }
        #expect(model.game.state.overframes.isEmpty)
        model.unlockOnLaunch()
        #expect(model.game.state.overframes == [1] && store.load().overframes == [1])
    }

    /// 가져오기는 두 세이브의 해금을 합치고, 가져온 세이브의 3장 카드도 해금하며, 그림이 없는 cid 는 버린다
    @MainActor @Test func importMergesAndGrantsUnlocks() throws {
        let db = oneBoxDB([1: overframeCard("카드1"), 2: overframeCard("카드2", 1), 3: card("카드3")])
        let (model, store) = try makeModel(db) { $0.overframes = [1] }
        var incoming = GameState()
        incoming.owned[2] = 3
        incoming.overframes = [3, 999]
        _ = try model.importSave(SaveEnvelope(appVersion: "0", exportedAt: Date(), state: incoming))
        #expect(model.game.state.overframes == [1, 2] && store.load().overframes == [1, 2])
    }
}
#endif
