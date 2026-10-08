import Testing
@testable import YugiTokenBar

@Suite struct MonsterGuaranteeTests {
    /// 마법·함정이 대부분인 팩이라도 한 봉투에 몬스터가 최소 `monstersPerPack` 장 나온다.
    @Test func packHasAtLeastTwoMonsters() {
        func info(_ attr: String, _ tier: Int) -> CardInfo {
            CardInfo(name: "", attr: attr, level: nil, type: nil, atk: nil, def: nil, text: "", imageId: nil, tier: tier,
                     kindCode: ["마법": "spell", "함정": "trap"][attr])
        }
        var cards: [Int: CardInfo] = [:]
        var list: [Int] = []
        for cid in 1...10 {  // 노멀 10장: 몬스터 2 + 마법 8
            cards[cid] = info(cid <= 2 ? "빛" : "마법", 1)
            list.append(cid)
        }
        for cid in 11...12 {  // 레어 2장: 함정
            cards[cid] = info("함정", 2)
            list.append(cid)
        }
        let db = CardDB(packs: [Pack(pid: "p", name: "팩", date: "2004-01-01", cards: list)], cards: cards)
        var rng = SeededRNG(seed: 7)
        for _ in 0..<200 {
            var game = Game(db: db, state: GameState())
            game.state.coins = Balance.packPrice
            let pulls = game.buy(pack: 0, using: &rng)
            #expect(pulls.count == 5)
            #expect(pulls.filter { db.cards[$0.cid]?.kind == .monster }.count >= Balance.monstersPerPack)
        }
    }
}
