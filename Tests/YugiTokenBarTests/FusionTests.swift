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
            CardDB.fusionSpell: CardInfo(name: "융합", attr: "마법", level: nil, type: "일반", atk: nil, def: nil, text: "", imageId: nil, tier: 3),
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
        #expect(game.state.owned == [2: 1, 10: 1, CardDB.fusionSpell: 1])  // 소재1은 마지막 장이라 빠지고, 소재2는 2장만 소비, 「융합」은 남는다
        #expect(game.state.log.first?.cid == 10 && game.state.log.first?.source == "융합")
        let unknown = game.fuse(11)
        #expect(game.fusionMaterials(11) == nil && !unknown)  // 소재를 모르는 융합은 못 만든다
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
}
