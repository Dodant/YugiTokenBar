import Foundation
import Testing
@testable import YugiTokenBar

@Suite struct CardDBTests {
    @Test func bundledDataMatchesKoreanBoostersThroughModern() throws {
        let db = try CardDB.load(from: CardDB.repoCardsURL)
        #expect(db.packs.count == 100)
        #expect(db.packs.first?.name == "푸른 눈의 백룡의 전설")
        #expect(db.packs.last?.name == "카오스 오리진즈")
        #expect(!db.packs.contains { $0.name.contains("어시스트") || $0.cards.count < 40 })  // 미니 팩은 뺀다
        #expect(db.packs.allSatisfy { $0.date < "2026-07-15" })
        #expect(db.packs.map(\.date) == db.packs.map(\.date).sorted())
        #expect(db.packs.first?.setCode == "LOB")
        #expect(db.eras.map(\.name) == ["DM", "GX", "5D's", "ZEXAL", "ARC-V", "VRAINS", "Modern"])
        let kinds = Dictionary(grouping: db.cards.values, by: \.kind).mapValues(\.count)
        #expect(kinds == ["몬스터": 5033, "마법": 1719, "함정": 1420])
        // 팩마다 노멀 몬스터가 보장 장 수 이상이라 몬스터 슬롯이 다른 티어로 올라가지 않는다
        #expect(db.packs.allSatisfy { p in p.cards.filter { $0.tier == 1 && db.cards[$0.cid]?.kind == "몬스터" }.count >= Balance.monstersPerPack })
        #expect(db.eras.map(\.packs) == [0..<11, 11..<27, 27..<43, 43..<51, 51..<63, 63..<75, 75..<100])
        // 시대 첫 팩: 듀얼리스트의 투혼(GX), 듀얼리스트의 태동(싱크로), 리턴 오브 더 듀얼리스트(엑시즈), 더 듀얼리스트 어드벤트(펜듈럼), 코드 오브 더 듀얼리스트(링크), 라이즈 오브 더 듀얼리스트(Modern)
        #expect(db.eras.map { db.packs[$0.packs.lowerBound].setCode } == ["LOB", "SOD", "TDGS", "REDU", "DUEA", "COTD", "ROTD"])
        #expect(db.packs.allSatisfy { $0.setCode != nil && $0.imageURL != nil })
        #expect(db.packs.allSatisfy { $0.imageURL!.contains("BoosterKR") })  // 100팩 모두 한글판
        #expect(db.allCIDs.count == 8172)
        // 재수록 카드는 모든 팩에서 가장 높은 등급: 유벨(환영의 어둠 N, 팬텀 나이트메어 QCSE → SE)
        #expect(Dictionary(grouping: db.packs.flatMap(\.cards), by: \.cid).values.allSatisfy { Set($0.map(\.tier)).count == 1 })
        #expect(db.packs.flatMap(\.cards).filter { db.cards[$0.cid]?.name == "유벨" }.map(\.label) == ["SE", "SE"])
        for pack in db.packs {
            for card in pack.cards {
                #expect(db.cards[card.cid] != nil, "팩 \(pack.name) 의 cid \(card.cid) 가 cards 에 없음")
                #expect((1...5).contains(card.tier))
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
        // 종류 메뉴의 소환법: 의식 마법(댄스의 유혹)은 "의식"에 안 잡히고, 엑시즈 펜듈럼(패왕흑룡)은 둘 다
        #expect(db.cards[4682]?.matches(kind: "의식") == false && db.cards[4682]?.matches(kind: "마법") == true)
        #expect(["몬스터", "엑시즈", "펜듈럼"].allSatisfy { db.cards[11835]?.matches(kind: $0) == true })
        #expect(db.cards.values.filter { $0.matches(kind: "융합") }.count == 286)
        // 융합 소재(build-cards.py 가 효과 첫 줄에서 뗀다): NEX 2종·베어트론 빼고 283종, 전부 100팩 카드인 건 83종
        let fusions = db.cards.values.filter { $0.matches(kind: "융합") }
        #expect(fusions.filter { $0.materials != nil }.count == 283)
        #expect(fusions.filter { $0.materials?.allSatisfy { $0.cid != nil } == true }.count == 83)
        #expect(db.cards[20769]?.materials?.first == Material(rule: "\"엘리멘틀 히어로 페더맨\"이나 \"엘리멘틀 히어로 버스트 레이디\""))  // "A"이나 "B" 는 조건
        #expect(db.cards[4043]?.materials == [Material(cid: 4044), Material(cid: 4045)] && db.cards[4043]?.text == "")  // 용기사 가이아: 바닐라라 효과가 빈다
        #expect(db.cards[4098]?.materials?.first == Material(name: "미노타우로스"))  // 미노켄타우로스: 스타터 덱 카드라 100팩에 없다
        #expect(fusions.allSatisfy { !$0.text.contains("＋") })
        // 「융합」 마법은 첫 팩에 있어서 어느 시대 범위에서도 구할 수 있다
        #expect(db.cards[CardDB.fusionSpell].map { ($0.name, $0.kind) } ?? ("", "") == ("융합", "마법"))
        #expect(db.packs[0].cards.contains { $0.cid == CardDB.fusionSpell })
        #expect(db.materialNeed[6390] == 3 && db.materialNeed[4007] == 2)  // 사이버 드래곤(사이버 엔드 드래곤), 푸른 눈의 백룡(쌍폭렬룡)
        #expect(db.prefix(packs: 11).materialNeed[6390] == nil)  // DM 범위엔 사이버 드래곤을 쓰는 융합이 없다
        // 소재를 다 아는 융합(융합 전용 후보)의 소재는 어느 시대 범위에서도 그 융합과 같은 범위 안에 있다 → Game.isFusionOnly 가 범위 검사를 안 한다
        for era in db.eras {
            let sub = db.prefix(packs: era.packs.upperBound)
            #expect(sub.allCIDs.allSatisfy { cid in
                let mats = sub.cards[cid]?.materials ?? []
                return !mats.allSatisfy { $0.cid != nil } || mats.allSatisfy { sub.cidSet.contains($0.cid!) }
            }, "\(era.name)까지: 소재가 범위 밖인 융합 전용 카드가 있음")
        }
    }
}

/// 이름순 키: Finder 순서(숫자는 크기순), 같은 이름은 같은 순위(그 안에서는 팩 순번으로 정렬된다)
@Test func nameRanksFollowFinderOrderAndTieEqualNames() {
    func info(_ name: String) -> CardInfo {
        CardInfo(name: name, attr: nil, level: nil, type: nil, atk: nil, def: nil, text: "", imageId: nil)
    }
    let r = CardDB.nameRanks([1: info("카드10"), 2: info("카드2"), 3: info("가"), 4: info("카드2")])
    #expect(r[3]! < r[2]! && r[2]! < r[1]!)
    #expect(r[2] == r[4])
}
