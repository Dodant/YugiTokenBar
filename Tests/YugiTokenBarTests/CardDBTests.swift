import Foundation
import Testing
@testable import YugiTokenBar

@Suite struct CardDBTests {
    @Test func bundledDataMatchesKoreanBoostersThroughModern() throws {
        let db = try CardDB.load(from: CardDB.repoURL("ko"))
        #expect(db.packs.count == 100)
        #expect(db.packs.first?.name == "푸른 눈의 백룡의 전설")
        #expect(db.packs.last?.name == "카오스 오리진즈")
        #expect(!db.packs.contains { $0.name.contains("어시스트") || $0.cards.count < 40 })  // 미니 팩은 뺀다
        #expect(db.packs.allSatisfy { $0.date < "2026-07-15" })
        #expect(db.packs.map(\.date) == db.packs.map(\.date).sorted())
        #expect(db.packs.first?.setCode == "LOB")
        #expect(db.eras.map(\.name) == ["DM", "GX", "5D's", "ZEXAL", "ARC-V", "VRAINS", "Modern"])
        let kinds = Dictionary(grouping: db.cards.values, by: \.kind).mapValues(\.count)
        #expect(kinds == [.monster: 5086, .spell: 1720, .trap: 1420])
        // 팩마다 노멀 몬스터가 보장 장 수 이상이라 몬스터 슬롯이 다른 티어로 올라가지 않는다
        #expect(db.packs.allSatisfy { p in p.cards.filter { db.tier($0) == 1 && db.cards[$0]?.kind == .monster }.count >= Balance.monstersPerPack })
        #expect(db.eras.map(\.packs) == [0..<11, 11..<27, 27..<43, 43..<51, 51..<63, 63..<75, 75..<100])
        // 시대 첫 팩: 듀얼리스트의 투혼(GX), 듀얼리스트의 태동(싱크로), 리턴 오브 더 듀얼리스트(엑시즈), 더 듀얼리스트 어드벤트(펜듈럼), 코드 오브 더 듀얼리스트(링크), 라이즈 오브 더 듀얼리스트(Modern)
        #expect(db.eras.map { db.packs[$0.packs.lowerBound].setCode } == ["LOB", "SOD", "TDGS", "REDU", "DUEA", "COTD", "ROTD"])
        #expect(db.packs.allSatisfy { $0.setCode != nil && $0.imageURL != nil })
        #expect(db.packs.allSatisfy { $0.imageURL!.contains("BoosterKR") })  // 100팩 모두 한글판
        #expect(db.allCIDs.count == 8226)
        // 재수록 카드는 수록 팩 중 가장 높은 등급: 유벨(환영의 어둠 N, 팬텀 나이트메어 QCSE → SE)
        #expect(db.cards.values.first { $0.name == "유벨" }?.rarity == "SE")
        let tiers = Dictionary(grouping: db.cards.values, by: \.tier).mapValues(\.count)
        #expect(tiers == [1: 4774, 2: 1733, 3: 907, 4: 502, 5: 310])
        // 팩 표지 몬스터는 SE (악몽의 미궁·어둠의 유산은 표지가 마법·함정이라 빠진다)
        #expect(db.cards[4007]?.rarity == "SE" && db.cards[4223]?.rarity == "SE")  // 푸른 눈의 백룡, 블랙 데몬즈 드래곤
        for pack in db.packs {
            for cid in pack.cards {
                #expect(db.cards[cid] != nil, "팩 \(pack.name) 의 cid \(cid) 가 cards 에 없음")
            }
        }
        #expect(db.cards.values.allSatisfy { !$0.name.isEmpty && $0.imageId != nil })
        #expect(db.cards[4007]?.name == "푸른 눈의 백룡")
        #expect(db.cards[4007]?.imageId == 89631139)
        #expect(db.cards[13042]?.levelKind == .level)
        #expect(db.cards.values.first { $0.name == "파이어월 드래곤" }.map { $0.levelKind == .link && $0.level == 4 } == true)
        #expect(db.cards[11835]?.levelKind == .rank)  // 엑시즈 펜듈럼은 랭크
        #expect(db.cards.values.first { $0.name == "파이어월 드래곤" }?.def == nil)
        #expect(db.cards[11786]?.scale == 2 && db.cards[11786]?.pendulum?.isEmpty == false)  // 소환사 라이즈벨트
        #expect(db.cards.values.allSatisfy { $0.pendulum?.isEmpty != true && !$0.text.contains("<br>") })
        // 종류 메뉴의 소환법: 의식 마법(댄스의 유혹)은 "의식"에 안 잡히고, 엑시즈 펜듈럼(패왕흑룡)은 둘 다
        #expect(db.cards[4682]?.matches(kind: "ritual") == false && db.cards[4682]?.matches(kind: "spell") == true)
        #expect(["monster", "xyz", "pendulum"].allSatisfy { db.cards[11835]?.matches(kind: $0) == true })
        #expect(db.cards.values.filter { $0.matches(kind: "fusion") }.count == 323)
        // 융합 소재(build-cards.py 가 효과 첫 줄에서 뗀다): 마스크드 히어로 10종·NEX 2종·베어트론 빼고 310종, 전부 카드인 건 118종
        let fusions = db.cards.values.filter { $0.matches(kind: "fusion") }
        #expect(fusions.filter { $0.materials != nil }.count == 310)
        #expect(fusions.filter { $0.materials?.allSatisfy { $0.cid != nil } == true }.count == 118)
        #expect(db.cards[20769]?.materials?.first == Material(rule: "\"엘리멘틀 히어로 페더맨\"이나 \"엘리멘틀 히어로 버스트 레이디\""))  // "A"이나 "B" 는 조건
        #expect(db.cards[4043]?.materials == [Material(cid: 4044), Material(cid: 4045)] && db.cards[4043]?.text == "")  // 용기사 가이아: 바닐라라 효과가 빈다
        // 조건 없는 융합의 100팩에 없는 소재 8장은 그 융합이 든 팩에 넣는다: 미노켄타우로스의 미노타우로스(스타터 덱 카드, 강철의 습격자)
        #expect(db.cards[4098]?.materials?.first == Material(cid: 4032) && db.packs[1].cards.contains(4032))
        // 100팩 밖 융합 중 조건 없고 100팩 소재가 있는 25종은 100팩 소재가 처음 나온 팩 중 가장 늦은 팩에 넣는다: 합체마신－게이트 가디언(강철의 습격자)
        #expect(db.packs[1].cards.contains(18325) && db.cards[18325]?.materials == [Material(cid: 4377), Material(cid: 4378), Material(cid: 4379)])
        // 밖 소재도 같은 팩에: 극화염의 검사(화염의 검사 + 조건 융합 투의염참룡), 메테오 블랙 드래곤(붉은 눈의 흑룡 + 메테오 드래곤)
        #expect(db.cards[19727]?.materials == [Material(cid: 4021), Material(cid: 19728)] && [19727, 19728, 4719, 4718].allSatisfy(db.packs[0].cards.contains))
        #expect(db.cards[4121] == nil)  // 카오스 위저드: 소재 흑마족의 커튼이 한국 미발매
        // 마스크 체인지·마스크드 히어로 10종은 한국 첫 수록일 직전 팩에: 마스크 체인지(익스트림 빅토리), 아토믹(듀얼리스트 어드밴스)
        #expect(db.packs.firstIndex { $0.cards.contains(CardDB.maskChange) } == 38 && db.cards[CardDB.maskChange]?.kind == .spell)
        #expect(db.packs.firstIndex { $0.cards.contains(21614) } == 95 && db.cards.values.filter { $0.mask == true }.count == 10)
        #expect(db.cards.values.filter { $0.hero == true }.count == 87 && db.fusionCIDs.count == 305)
        // 조건이 섞인 융합의 100팩 밖 소재도 그 융합의 팩에 넣어서 이름만 남은 소재가 없다: 지천의 기사 가이아드레이크의 대지의 기사 가이아 나이트(폭풍의 스타스트라이크)
        #expect(db.cards.values.allSatisfy { $0.materials?.allSatisfy { $0.name == nil } ?? true })
        #expect(db.cards[9116]?.materials?.first == Material(cid: 7697) && db.packs[36].cards.contains(7697))
        #expect(fusions.allSatisfy { !$0.text.contains("＋") })
        // 조건 소재가 단순한(테마 포함) 융합 177종은 맞는 카드 목록(picks)이 있다: 투의염참룡(자기 빼고 드래곤족 + 전사족 / 화염 속성)
        #expect(db.cards.values.filter { $0.picks != nil }.count == 177)
        #expect(db.cards[12777]?.picks?.first?.any.contains(6315) == true)  // 앤틱 기어 데블의 "앤틱 기어" 몬스터에 앤틱 기어 골렘
        #expect(db.cards[19728]?.picks?.map(\.any.count) == [437, 74] && db.cards[19728]?.picks?[0].any.contains(4007) == true)
        #expect(db.cards[12953]?.picks?.map { $0.join == true } == [false, true, true, true])  // 패왕룡 즈아크: 종류마다 1장씩
        // 「융합」 마법은 첫 팩에 있어서 어느 시대 범위에서도 구할 수 있다
        #expect(db.cards[CardDB.fusionSpell].map { ($0.name, $0.kind) } ?? ("", .monster) == ("융합", .spell))
        #expect(db.packs[0].cards.contains(CardDB.fusionSpell))
        #expect(db.materialNeed[6390] == 3 && db.materialNeed[4007] == 3)  // 사이버 드래곤(사이버 엔드 드래곤), 푸른 눈의 백룡(궁극의 푸른 눈의 백룡)
        #expect(db.prefix(packs: 11).materialNeed[6390] == nil)  // DM 범위엔 사이버 드래곤을 쓰는 융합이 없다
        // fusionCount 는 만들 수 있는 카드(소재를 아는 융합·마스크드 히어로) 수를 미리 센 값이라 전체·시대 범위 DB 모두 필터 식과 같아야 한다
        // 언어 무관 코드: 마법·함정만 kind 가 있고, summons 는 몬스터에만, 시대 순 코드만
        #expect(db.cards.values.allSatisfy { [nil, "spell", "trap"].contains($0.kindCode) })
        #expect(db.cards.values.allSatisfy { $0.summons == nil || ($0.kind == .monster && $0.summons!.allSatisfy(CardInfo.summonCodes.contains)) })
        #expect(db.cards[11835]?.summons == ["xyz", "pendulum"])
        for d in [db, db.prefix(packs: 30)] {
            #expect(d.fusionCount == d.allCIDs.filter { d.cards[$0]?.craftable == true }.count && d.fusionCount > 0)
        }
        // 소재를 다 아는 융합(융합 전용 후보)의 소재는 어느 시대 범위에서도 그 융합과 같은 범위 안에 있다 → Game.isFusionOnly 가 범위 검사를 안 한다
        for era in db.eras {
            let sub = db.prefix(packs: era.packs.upperBound)
            #expect(sub.allCIDs.allSatisfy { cid in
                let mats = sub.cards[cid]?.materials ?? []
                return !mats.allSatisfy { $0.cid != nil } || mats.allSatisfy { sub.cidSet.contains($0.cid!) }
            }, "\(era.name)까지: 소재가 범위 밖인 융합 전용 카드가 있음")
            // 마스크드 히어로도 「마스크 체인지」와 같은 속성 HERO 가 같은 범위 안에 있다
            #expect(sub.allCIDs.filter { sub.cards[$0]?.mask == true }.allSatisfy { cid in
                sub.cidSet.contains(CardDB.maskChange) && sub.allCIDs.contains { $0 != cid && sub.cards[$0]?.hero == true && sub.cards[$0]?.attr == sub.cards[cid]?.attr }
            }, "\(era.name)까지: 마스크 체인지나 같은 속성 HERO 가 범위 밖인 마스크드 히어로가 있음")
            // 조건 소재 융합도 소재 줄의 카드와 조건마다 맞는 카드가 같은 범위 안에 있다 (한 카드를 여러 장 모으면 장 수는 채운다)
            #expect(sub.allCIDs.allSatisfy { cid in
                guard let card = sub.cards[cid], let picks = card.picks else { return true }
                return card.cardMaterials.keys.allSatisfy(sub.cidSet.contains) && picks.allSatisfy { !$0.any.isDisjoint(with: sub.cidSet) }
            }, "\(era.name)까지: 조건에 맞는 카드가 범위 밖인 조건 소재 융합이 있음")
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

/// cards_XX.json 에 범위 밖 등급이 있어도 1~5 로 잘라 읽는다 (Pull.label 등이 죽지 않게)
@Test func outOfRangeTiersAreClamped() {
    func card(_ tier: Int) -> CardInfo {
        CardInfo(name: "", attr: nil, level: nil, type: nil, atk: nil, def: nil, text: "", imageId: nil, tier: tier)
    }
    let db = CardDB(packs: [], cards: [1: card(0), 2: card(9), 3: card(3)])
    #expect([1, 2, 3].map(db.tier) == [1, 5, 3])
    #expect(Pull(cid: 2, tier: db.tier(2), isNew: true).label == "SE")
}

/// 언어별 카드 파일 이름: ko → KO, ja → JP, en → EN (모르는 언어는 EN)
@Test func cardFileNamePerLanguage() {
    #expect(["ko", "ja", "en", "fr"].map(CardDB.fileName) == ["cards_KO", "cards_JP", "cards_EN", "cards_EN"])
    #expect(CardDB.repoURL("ko").lastPathComponent == "cards_KO.json")
}
