import Foundation
import Testing
@testable import YugiTokenBar

@Suite struct CardDBTests {
    @Test func bundledDataMatchesKoreanBoostersThroughVRAINS() throws {
        let db = try CardDB.load(from: CardDB.repoCardsURL)
        #expect(db.packs.count == 75)
        #expect(db.packs.first?.name == "푸른 눈의 백룡의 전설")
        #expect(db.packs.last?.name == "이터니티 코드")
        #expect(db.packs.allSatisfy { $0.date < "2020-07-25" })
        #expect(db.packs.map(\.date) == db.packs.map(\.date).sorted())
        #expect(db.packs.first?.setCode == "LOB")
        #expect(db.eras.map(\.name) == ["DM", "GX", "5D's", "ZEXAL", "ARC-V", "VRAINS"])
        let kinds = Dictionary(grouping: db.cards.values, by: \.kind).mapValues(\.count)
        #expect(kinds == ["몬스터": 3774, "마법": 1260, "함정": 1126])
        // 팩마다 노멀 몬스터가 보장 장 수 이상이라 몬스터 슬롯이 다른 티어로 올라가지 않는다
        #expect(db.packs.allSatisfy { p in p.cards.filter { $0.tier == 1 && db.cards[$0.cid]?.kind == "몬스터" }.count >= Balance.monstersPerPack })
        #expect(db.eras.map(\.packs) == [0..<11, 11..<27, 27..<43, 43..<51, 51..<63, 63..<75])
        // 시대 첫 팩: 듀얼리스트의 투혼(GX), 듀얼리스트의 태동(싱크로), 리턴 오브 더 듀얼리스트(엑시즈), 더 듀얼리스트 어드벤트(펜듈럼), 코드 오브 더 듀얼리스트(링크)
        #expect(db.eras.map { db.packs[$0.packs.lowerBound].setCode } == ["LOB", "SOD", "TDGS", "REDU", "DUEA", "COTD"])
        #expect(db.packs.allSatisfy { $0.setCode != nil && $0.imageURL != nil })
        #expect(db.packs.allSatisfy { $0.imageURL!.contains("BoosterKR") })  // 75팩 모두 한글판
        #expect(db.allCIDs.count == 6160)
        for pack in db.packs {
            for card in pack.cards {
                #expect(db.cards[card.cid] != nil, "팩 \(pack.name) 의 cid \(card.cid) 가 cards 에 없음")
                #expect((1...4).contains(card.tier))
            }
        }
        #expect(db.cards.values.allSatisfy { !$0.name.isEmpty && $0.imageId != nil })
        #expect(db.cards[4007]?.name == "푸른 눈의 백룡")
        #expect(db.cards[4007]?.imageId == 89631139)
        #expect(db.cards[13042]?.levelName == "레벨")
        #expect(db.cards.values.first { $0.name == "파이어월 드래곤" }.map { [$0.levelName, "\($0.level!)"] } == ["링크", "4"])
        #expect(db.cards.values.first { $0.name == "파이어월 드래곤" }?.def == nil)
        #expect(db.cards[11786]?.scale == 2 && db.cards[11786]?.pendulum?.isEmpty == false)  // 소환사 라이즈벨트
        #expect(db.cards.values.allSatisfy { $0.pendulum?.isEmpty != true && !$0.text.contains("<br>") })
    }
}
