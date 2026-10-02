import Foundation
import Testing
@testable import YugiTokenBar

@Suite struct CardDBTests {
    @Test func bundledDataMatchesKoreanPreSynchroBoosters() throws {
        let db = try CardDB.load(from: CardDB.repoCardsURL)
        #expect(db.packs.count == 27)
        #expect(db.packs.first?.name == "푸른 눈의 백룡의 전설")
        #expect(db.packs.last?.name == "파괴의 빛")
        #expect(db.packs.allSatisfy { $0.date < "2008-10-07" })
        #expect(db.packs.map(\.date) == db.packs.map(\.date).sorted())
        #expect(db.packs.first?.setCode == "LOB")
        #expect(db.eras.map(\.name) == ["DM", "GX"])
        let kinds = Dictionary(grouping: db.cards.values, by: \.kind).mapValues(\.count)
        #expect(kinds == ["몬스터": 1341, "마법": 511, "함정": 418])
        #expect(db.eras.map(\.packs) == [0..<11, 11..<27])  // 천공의 성역까지 DM, 듀얼리스트의 투혼부터 GX
        #expect(db.packs.allSatisfy { $0.setCode != nil && $0.imageURL != nil })
        #expect(db.packs.allSatisfy { $0.imageURL!.contains("BoosterKR") })  // 27팩 모두 한글판
        #expect(db.allCIDs.count == 2270)
        for pack in db.packs {
            for card in pack.cards {
                #expect(db.cards[card.cid] != nil, "팩 \(pack.name) 의 cid \(card.cid) 가 cards 에 없음")
                #expect((1...4).contains(card.tier))
            }
        }
        #expect(db.cards.values.allSatisfy { !$0.name.isEmpty && $0.imageId != nil })
        #expect(db.cards[4007]?.name == "푸른 눈의 백룡")
        #expect(db.cards[4007]?.imageId == 89631139)
    }
}
