import Testing
@testable import YugiTokenBar

@Suite struct FusionTests {
    /// 팩0: 노멀 1·2·3, 「융합」 마법(해금 카드), UR 10 = 1 + 2 + 2 (소재를 다 아는 융합), UR 11 = 1 + 100팩에 없는 카드
    let db: CardDB = {
        func info(_ name: String, _ materials: [Material]? = nil) -> CardInfo {
            CardInfo(name: name, attr: nil, level: nil, type: materials == nil ? "전사족/일반" : "전사족/융합",
                     atk: nil, def: nil, text: "", imageId: nil, tier: materials == nil ? 1 : 4, materials: materials)
        }
        let cards: [Int: CardInfo] = [
            1: info("소재1"), 2: info("소재2"), 3: info("다른 카드"),
            CardDB.fusionSpell: CardInfo(name: "융합", attr: "마법", level: nil, type: "일반", atk: nil, def: nil, text: "", imageId: nil, tier: 3, kindCode: "spell"),
            10: info("융합", [Material(cid: 1), Material(cid: 2), Material(cid: 2)]),
            11: info("조건 융합", [Material(cid: 1), Material(name: "없는 카드")]),
        ]
        let list = [1, 2, 3, CardDB.fusionSpell, 10, 11]
        return CardDB(packs: [Pack(pid: "p", name: "팩", date: "2004-01-01", cards: list)], cards: cards)
    }()

    @Test func fuseConsumesMaterialsAndGivesOne() {
        var game = Game(db: db, state: GameState())
        game.state.owned = [1: 1, 2: 3]
        #expect(game.fusionMaterials(10) == [1: 1, 2: 2])
        #expect(!game.hasFusionSpell && !game.canFuse(10))  // 「융합」 카드가 없으면 소재가 있어도 잠김
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
        #expect(game.fusionMaterials(11) == nil && !unknown)  // 소재를 모르는 융합은 못 만든다
    }

    /// 마스크드 히어로: 「마스크 체인지」가 있으면 같은 속성 HERO 중 가장 많이 가진 1장을 소비해(마지막 장은 남김) 만든다
    @Test func maskChangeUsesSameAttributeHero() {
        func hero(_ attr: String, mask: Bool? = nil) -> CardInfo {
            CardInfo(name: "히어로", attr: attr, level: nil, type: "전사족", atk: nil, def: nil, text: "", imageId: nil, hero: true, mask: mask)
        }
        let cards: [Int: CardInfo] = [1: hero("빛"), 2: hero("빛"), 3: hero("어둠"), 4: CardInfo(name: "빛 몬스터", attr: "빛", level: nil, type: "전사족", atk: nil, def: nil, text: "", imageId: nil),
                                      20: hero("빛", mask: true), CardDB.maskChange: CardInfo(name: "마스크 체인지", attr: "마법", level: nil, type: "속공", atk: nil, def: nil, text: "", imageId: nil, kindCode: "spell")]
        let db = CardDB(packs: [Pack(pid: "p", name: "팩", date: "2004-01-01", cards: cards.keys.sorted())], cards: cards)
        var game = Game(db: db, state: GameState())
        game.state.owned = [3: 5, 4: 5]
        game.state.fusionOnly = true
        #expect(game.maskMaterial(20) == nil && !game.canFuse(20))  // 빛 HERO 가 없다 (어둠 HERO·HERO 아닌 빛 몬스터는 안 된다)
        game.state.owned[1] = 2
        game.state.owned[2] = 3
        #expect(game.maskMaterial(20) == 2 && !game.canFuse(20))  // 「마스크 체인지」가 없으면 잠김
        game.state.owned[CardDB.maskChange] = 1
        #expect(game.fusable == [20] && db.fusionCIDs.contains(20) && game.isFusionOnly(20))
        let made = game.fuse(20)
        #expect(made && game.state.owned[2] == 2 && game.state.owned[1] == 2 && game.state.owned[20] == 1 && game.state.owned[CardDB.maskChange] == 1)
    }

    /// 조건 소재: 소재 줄의 카드를 먼저 잡고, 조건마다 맞는 카드 중 남는 장 수가 많은 것부터 채운다 (마지막 장은 남김)
    @Test func picksUseMostOwnedMatchingCards() {
        func mon(_ name: String) -> CardInfo { CardInfo(name: name, attr: nil, level: nil, type: "드래곤족", atk: nil, def: nil, text: "", imageId: nil) }
        var fusion = mon("융합 용")
        fusion.materials = [Material(cid: 1), Material(rule: "드래곤족 몬스터", count: 2)]
        fusion.picks = [Pick(any: [1, 2, 3], count: 2)]
        var each = mon("패왕")
        each.materials = [Material(rule: "드래곤족의 일반 / 효과 몬스터 1장씩 합계 2장")]
        each.picks = [Pick(any: [3]), Pick(any: [4], join: true)]
        let cards: [Int: CardInfo] = [1: mon("용 1"), 2: mon("용 2"), 3: mon("용 3"), 4: mon("다른 몬스터"), 20: fusion, 21: each,
                                      CardDB.fusionSpell: CardInfo(name: "융합", attr: "마법", level: nil, type: "일반", atk: nil, def: nil, text: "", imageId: nil, kindCode: "spell")]
        let db = CardDB(packs: [Pack(pid: "p", name: "팩", date: "2004-01-01", cards: cards.keys.sorted())], cards: cards)
        var game = Game(db: db, state: GameState())
        game.state.owned = [1: 1, 4: 9, CardDB.fusionSpell: 1]
        game.state.fusionOnly = true
        #expect(game.pickMaterials(20) == nil && !game.canFuse(20))  // 용 1 은 소재 줄 몫이라 조건에 못 쓴다
        game.state.owned[1] = 2
        game.state.owned[2] = 1
        #expect(game.pickMaterials(20) == [[1: 1, 2: 1]])  // 장 수가 모자라면 다른 카드로 나눠 채운다
        game.state.owned[3] = 4
        #expect(game.pickMaterials(20) == [[3: 2]] && Set(game.fusable) == [20, 21] && db.fusionCIDs.contains(20))
        let made = game.fuse(20)
        #expect(made && game.state.owned[1] == 1 && game.state.owned[3] == 2 && game.state.owned[20] == 1)
        #expect(game.pickMaterials(21) == [[3: 1, 4: 1]])  // "1장씩 합계" 를 나눈 조건은 한 줄로 합친다
    }

    /// 오른쪽 "융합 가능" 목록: 설정·「융합」·소재가 다 있어야 나온다
    @Test func fusableListsOnlyReadyFusions() {
        var game = Game(db: db, state: GameState())
        game.state.owned = [1: 1, 2: 2, CardDB.fusionSpell: 1]
        #expect(game.fusable.isEmpty)  // 설정이 꺼져 있으면 없다
        game.state.fusionOnly = true
        #expect(game.fusable == [10])  // 11 은 소재를 몰라서 빠진다
        game.state.owned[10] = 1
        #expect(game.fusable.isEmpty)  // 이미 가진 융합 몬스터는 안 띄운다
        game.state.owned[10] = nil
        game.state.owned[CardDB.fusionSpell] = nil
        #expect(game.fusable.isEmpty)
    }

    /// 융합 전용 설정이 켜져 있으면 소재는 필요한 최대 장 수(소재2 → 2장)까지 중복으로 치지 않는다
    @Test func fusionOnlyKeepsMaterialCopiesFromDuplicateSales() {
        var state = GameState()
        state.owned = [2: 5, 3: 4]
        var game = Game(db: db, state: state)
        #expect(game.db.materialNeed == [1: 1, 2: 2])
        #expect(game.duplicatesValue.count == 7)  // 설정이 꺼져 있으면 1장만 남긴다
        game.state.fusionOnly = true
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
        game.state.fusionOnly = false
        for _ in 0..<20 { _ = game.buy(pack: 0, using: &rng) }
        #expect(game.copies(2) == 2)  // 끄면 더 쌓이지 않고, 이미 쌓인 건 그대로
    }

    @Test func fusionOnlyKeepsKnownFusionsOutOfPacksAndFreeCards() {
        var state = GameState()
        state.coins = 1_000_000
        #expect(!state.fusionOnly)  // 기본값
        state.fusionOnly = true
        var game = Game(db: db, state: state)
        var rng = SeededRNG(seed: 5)
        #expect(game.isFusionOnly(10) && !game.isFusionOnly(11))
        for _ in 0..<100 { _ = game.buy(pack: 0, using: &rng) }
        #expect(game.copies(10) == 0 && game.copies(11) > 0)  // 융합 전용은 안 나오고, 소재를 모르는 융합은 나온다
        for _ in 0..<300 { #expect(game.drawFree(using: &rng) != 10) }
        // UR 슬롯에 융합 전용뿐이면 아래 티어로 내려간다 (SR 「융합」)
        #expect(game.draw(pack: 0, tier: 4, excluding: [11], using: &rng) == CardDB.fusionSpell)
        game.state.fusionOnly = false
        var free: Set<Int> = []
        for _ in 0..<300 { if let cid = game.drawFree(using: &rng) { free.insert(cid) } }
        #expect(free.contains(10))
    }

    /// 남은 미보유가 융합 전용뿐이면 상점에선 다 모은 팩(CLEAR)이고, 융합 남은 장 수를 센다. 설정을 끄면 아니다.
    @Test func packClearedWhenOnlyFusionOnlyLeft() {
        var game = Game(db: db, state: GameState())
        game.state.owned = [1: 1, 2: 1, 3: 1, CardDB.fusionSpell: 1, 11: 1]
        #expect(!game.progress(0).cleared && game.progress(0).fusionLeft == 0)
        game.state.fusionOnly = true
        #expect(game.progress(0).cleared && !game.progress(0).complete && game.progress(0).fusionLeft == 1)
        game.state.owned[10] = 1
        #expect(game.progress(0).complete && game.progress(0).fusionLeft == 0)
    }
}
