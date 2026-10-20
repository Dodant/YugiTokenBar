import Testing
@testable import YugiTokenBar

@Suite struct FusionTests {
    /// 팩0: 노멀 1·2·3, 「융합」 마법(해금 카드), UR 10 = 1 + 2 + 2 (소재를 다 아는 융합), UR 11 = 1 + 101팩에 없는 카드
    let db: CardDB = {
        func info(_ name: String, _ materials: [Material]? = nil, picks: [Pick]? = nil) -> CardInfo {
            var c = card(name, type: materials == nil ? "전사족/일반" : "전사족/융합", tier: materials == nil ? 1 : 4)
            c.materials = materials
            c.picks = picks
            return c
        }
        let cards: [Int: CardInfo] = [
            1: info("소재1"), 2: info("소재2"), 3: info("다른 카드"),
            CardDB.fusionSpell: card("융합", attr: "마법", type: "일반", tier: 3, kind: "spell"),
            10: info("융합", [Material(cid: 1), Material(cid: 2), Material(cid: 2)], picks: [Pick(any: [1]), Pick(any: [2]), Pick(any: [2])]),
            11: info("조건 융합", [Material(cid: 1), Material(name: "없는 카드")]),
        ]
        let list = [1, 2, 3, CardDB.fusionSpell, 10, 11]
        return CardDB(packs: [Pack(pid: "p", name: "팩", date: "2004-01-01", cards: list)], cards: cards)
    }()

    @Test func fuseConsumesMaterialsAndGivesOne() {
        var game = Game(db: db, state: GameState())
        game.state.owned = [1: 1, 2: 3]
        #expect(game.craftMaterials(10) == [1: 1, 2: 2])
        #expect(game.copies(CardDB.fusionSpell) == 0 && !game.canFuse(10))  // 「융합」 카드가 없으면 소재가 있어도 잠김
        let locked = game.fuse(10)
        #expect(!locked)
        game.state.owned[CardDB.fusionSpell] = 1
        game.state.owned[2] = 1
        #expect(!game.canFuse(10))  // 소재2가 1장 모자람
        let short = game.fuse(10)
        #expect(!short)
        #expect(game.state.owned == [1: 1, 2: 1, CardDB.fusionSpell: 1])
        game.state.owned[2] = 3
        let fused = game.fuse(10)
        #expect(fused)
        #expect(game.state.owned == [1: 1, 2: 1, 10: 1, CardDB.fusionSpell: 1])  // 소재1은 마지막 장이라 남고, 소재2는 2장만 소비, 「융합」은 남는다
        #expect(game.state.log.first?.cid == 10 && game.state.log.first?.source == "융합")
        let unknown = game.fuse(11)
        #expect(game.craftMaterials(11) == nil && !unknown)  // 소재를 모르는 융합은 못 만든다
    }

    /// 소재를 1장씩만 가지면 소비가 없으니, 한 번 만든 융합은 팔아도 다시 만들 수 없다 (융합 → 판매 반복으로 코인을 찍지 못하게)
    @Test func madeFusionCannotBeFusedAgainEvenAfterSelling() {
        var game = Game(db: db, state: GameState())
        game.state.owned = [1: 1, 2: 2, CardDB.fusionSpell: 1]
        let first = game.fuse(10)
        game.state.owned[2] = 2  // 소재가 다시 충분해도
        let again = game.fuse(10)
        #expect(first && !again && !game.canFuse(10))  // 가지고 있으면 다시 못 만든다
        let sold = game.sell(10)
        #expect(sold != nil && game.copies(10) == 0)
        let afterSale = game.fuse(10)
        #expect(!afterSale && !game.canFuse(10) && !game.fusable.contains(10))  // 다 팔아도 못 만든다
        #expect(!game.isFusionOnly(10))  // 대신 팩·무료 카드에서 나온다
        #expect(game.state.owned == [1: 1, 2: 2, CardDB.fusionSpell: 1])
    }

    /// 팩에서 받은 융합(예전 세이브·만들 수 없게 된 뒤 받은 장)도 만든 것으로 센다
    @Test func receivedFusionCountsAsMade() {
        var game = Game(db: db, state: GameState())
        game.state.owned = [1: 1, 2: 2, CardDB.fusionSpell: 1]
        game.give(10, source: LogEntry.fusion)
        _ = game.sell(10)
        #expect(!game.canFuse(10) && !game.isFusionOnly(10))
    }

    /// 다른 Mac 세이브를 가져와도 이 Mac에서 만든 기록은 남는다 (기록이 지워지면 다시 만들어 팔 수 있다)
    @Test func importKeepsMadeFusions() {
        var local = GameState(), imported = GameState()
        local.crafted = [10]
        imported.crafted = [11]
        #expect(imported.withLedger(of: local).crafted == [10, 11])
    }

    /// 마스크드 히어로: 「마스크 체인지」가 있으면 같은 속성 HERO 중 가장 많이 가진 1장을 소비해(마지막 장은 남김) 만든다
    @Test func maskChangeUsesSameAttributeHero() {
        func hero(_ attr: String, mask: Bool? = nil) -> CardInfo {
            var c = card("히어로", attr: attr, type: "전사족")
            c.hero = true
            c.mask = mask
            return c
        }
        var masked = hero("빛", mask: true)
        masked.picks = [Pick(any: [1, 2])]  // build-cards.py: 자기 빼고 같은 속성 HERO
        let cards: [Int: CardInfo] = [1: hero("빛"), 2: hero("빛"), 3: hero("어둠"), 4: card("빛 몬스터", attr: "빛", type: "전사족"),
                                      20: masked, CardDB.maskChange: card("마스크 체인지", attr: "마법", type: "속공", kind: "spell")]
        let db = oneBoxDB(cards)
        var game = Game(db: db, state: GameState())
        game.state.owned = [3: 5, 4: 5]
        #expect(game.craftMaterials(20) == nil && !game.canFuse(20))  // 빛 HERO 가 없다 (어둠 HERO·HERO 아닌 빛 몬스터는 안 된다)
        game.state.owned[1] = 2
        game.state.owned[2] = 3
        #expect(game.craftMaterials(20) == [2: 1] && !game.canFuse(20))  // 「마스크 체인지」가 없으면 잠김
        game.state.owned[CardDB.maskChange] = 1
        #expect(game.fusable == [20] && db.fusionCIDs.contains(20) && game.isFusionOnly(20))
        let made = game.fuse(20)
        #expect(made && game.state.owned[2] == 2 && game.state.owned[1] == 2 && game.state.owned[20] == 1 && game.state.owned[CardDB.maskChange] == 1)
    }

    /// 조건 소재: 소재 줄의 카드를 먼저 잡고, 조건마다 맞는 카드 중 남는 장 수가 많은 것부터 채운다 (마지막 장은 남김)
    @Test func picksUseMostOwnedMatchingCards() {
        func mon(_ name: String) -> CardInfo { card(name, type: "드래곤족") }
        var fusion = mon("융합 용")
        fusion.materials = [Material(cid: 1), Material(rule: "드래곤족 몬스터", count: 2)]
        fusion.picks = [Pick(any: [1]), Pick(any: [1, 2, 3], count: 2)]
        var each = mon("패왕")
        each.materials = [Material(rule: "드래곤족의 일반 / 효과 몬스터 1장씩 합계 2장")]
        each.picks = [Pick(any: [3]), Pick(any: [4], join: true)]
        let cards: [Int: CardInfo] = [1: mon("용 1"), 2: mon("용 2"), 3: mon("용 3"), 4: mon("다른 몬스터"), 20: fusion, 21: each,
                                      CardDB.fusionSpell: card("융합", attr: "마법", type: "일반", kind: "spell")]
        let db = oneBoxDB(cards)
        var game = Game(db: db, state: GameState())
        game.state.owned = [1: 1, 4: 9, CardDB.fusionSpell: 1]
        #expect(game.pickMaterials(20) == nil && !game.canFuse(20))  // 용 1 은 소재 줄 몫이라 조건에 못 쓴다
        game.state.owned[1] = 2
        game.state.owned[2] = 1
        #expect(game.pickMaterials(20) == [[1: 1], [1: 1, 2: 1]])  // 장 수가 모자라면 다른 카드로 나눠 채운다
        game.state.owned[3] = 4
        #expect(game.pickMaterials(20) == [[1: 1], [3: 2]] && Set(game.fusable) == [20, 21] && db.fusionCIDs.contains(20))
        let made = game.fuse(20)
        #expect(made && game.state.owned[1] == 1 && game.state.owned[3] == 2 && game.state.owned[20] == 1)
        #expect(game.pickMaterials(21) == [[3: 1, 4: 1]])  // "1장씩 합계" 를 나눈 조건은 한 줄로 합친다
    }

    /// 오른쪽 "융합 가능" 목록: 「융합」·소재가 다 있어야 나온다
    @Test func fusableListsOnlyReadyFusions() {
        var game = Game(db: db, state: GameState())
        game.state.owned = [1: 1, 2: 2, CardDB.fusionSpell: 1]
        #expect(game.fusable == [10])  // 11 은 소재를 몰라서 빠진다
        game.state.owned[10] = 1
        #expect(game.fusable.isEmpty)  // 이미 가진 융합 몬스터는 안 띄운다
        game.state.owned[10] = nil
        game.state.owned[CardDB.fusionSpell] = nil
        #expect(game.fusable.isEmpty)
    }

    /// 일괄 융합: 목록을 다 만들고, 만든 융합이 소재인 융합도 이어서 만든다. 소재가 겹쳐 모자라면 앞 것만
    @Test func fuseAllChainsAndStopsWhenShort() {
        func mon(_ name: String, _ picks: [Pick]? = nil) -> CardInfo {
            var c = card(name, type: picks == nil ? "전사족" : "전사족/융합")
            c.materials = picks.map { $0.map { _ in Material(rule: "몬스터") } }
            c.picks = picks
            return c
        }
        let cards: [Int: CardInfo] = [1: mon("소재"), 20: mon("융합 A", [Pick(any: [1])]), 21: mon("융합 B", [Pick(any: [20])]),
                                      22: mon("융합 C", [Pick(any: [1], count: 3)]),
                                      CardDB.fusionSpell: card("융합", attr: "마법", type: "일반", kind: "spell")]
        let db = oneBoxDB(cards)
        var game = Game(db: db, state: GameState())
        game.state.owned = [1: 3, CardDB.fusionSpell: 1]
        #expect(Set(game.fusable) == [20, 22])
        #expect(game.fuseAll() == [20, 21])  // A 가 소재1을 써서 C(3장)는 모자라고, A 가 생겨 B 를 이어서 만든다
        #expect(game.state.owned[1] == 2 && game.state.owned[20] == 1 && game.state.owned[21] == 1 && game.state.owned[22] == nil)
        #expect(game.fuseAll().isEmpty)
    }

    /// 융합 소재는 필요한 최대 장 수(소재2 → 2장)까지 중복으로 치지 않는다
    @Test func fusionOnlyKeepsMaterialCopiesFromDuplicateSales() {
        var state = GameState()
        state.owned = [2: 5, 3: 4]
        var game = Game(db: db, state: state)
        #expect(game.db.materialNeed == [1: 1, 2: 2])
        #expect(game.keep(2) == 2 && game.keep(3) == 1 && game.keep(10) == 1)
        #expect(game.duplicatesValue.count == 6)
        _ = game.sellDuplicates()
        #expect(game.state.owned == [2: 2, 3: 1])
        // 자동 판매도 소재는 2장까지 쌓인 뒤에 판다 (팩0의 노멀 3장은 매 봉투 다 나온다)
        game.state.coins = 1_000_000
        game.state.autoSellDuplicates = true
        var rng = SeededRNG(seed: 9)
        for _ in 0..<20 { _ = game.buy(pack: 0, using: &rng) }
        #expect(game.copies(2) == 2 && game.copies(3) == 1)
    }

    /// 조건 소재("전사족 3장")는 그 융합을 만들기 전까지 3장 남기고, 만들고 나면 1장만 남긴다
    @Test func fusionOnlyKeepsConditionMaterialsUntilMade() {
        var c = card("조건 융합", type: "전사족/융합", tier: 4)
        c.materials = [Material(rule: "전사족", count: 3)]
        c.picks = [Pick(any: [1, 2], count: 3)]
        let plain = card("전사", type: "전사족/일반")
        let db = oneBoxDB([1: plain, 2: plain, 20: c])
        var game = Game(db: db, state: GameState())
        #expect(game.keep(1) == 3 && game.keep(2) == 3)
        game.state.owned[20] = 1
        #expect(game.keep(1) == 1)
    }

    @Test func fusionOnlyKeepsKnownFusionsOutOfPacksAndFreeCards() {
        var state = GameState()
        state.coins = 1_000_000
        var game = Game(db: db, state: state)
        var rng = SeededRNG(seed: 5)
        #expect(game.isFusionOnly(10) && !game.isFusionOnly(11))
        for _ in 0..<100 { _ = game.buy(pack: 0, using: &rng) }
        #expect(game.copies(10) == 0 && game.copies(11) > 0)  // 융합 전용은 안 나오고, 소재를 모르는 융합은 나온다
        for _ in 0..<300 { #expect(game.drawFree(using: &rng) != 10) }
        // UR 슬롯에 융합 전용뿐이면 아래 티어로 내려간다 (SR 「융합」)
        #expect(game.draw(pack: 0, tier: 4, excluding: [11], using: &rng) == CardDB.fusionSpell)
        game.state.owned[10] = 1  // 융합으로 만들었으면 팩에서도 나온다
        #expect(!game.isFusionOnly(10) && game.draw(pack: 0, tier: 4, excluding: [11], using: &rng) == 10)
    }

    /// 남은 미보유가 융합 전용뿐이면 상점에선 다 모은 팩(CLEAR)이고, 융합 남은 장 수를 센다.
    @Test func packClearedWhenOnlyFusionOnlyLeft() {
        var game = Game(db: db, state: GameState())
        game.state.owned = [1: 1, 2: 1, 3: 1, CardDB.fusionSpell: 1, 11: 1]
        #expect(game.progress(0).cleared && !game.progress(0).complete && game.progress(0).fusionLeft == 1)
        game.state.owned[10] = 1
        #expect(game.progress(0).complete && game.progress(0).fusionLeft == 0)
    }
}
