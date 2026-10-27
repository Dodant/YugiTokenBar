import Foundation
import Testing
@testable import YugiTokenBar

@Suite struct CardDBTests {
    @Test func bundledDataMatchesKoreanBoostersThroughModern() throws {
        let db = try CardDB.load(from: CardDB.repoURL("ko"))
        // 정규 부스터 101팩 + 듀얼리스트 팩 30팩, 시대 안에서 정규 부스터 뒤에 듀얼리스트 팩이라 마지막은 Modern 듀얼리스트 팩
        #expect(db.packs.count == 131)
        #expect(db.packs.first?.name == "푸른 눈의 백룡의 전설")
        #expect(db.packs.last?.name == "듀얼리스트 팩 -휘광의 듀얼리스트 편-")
        #expect(!db.packs.contains { $0.name.contains("어시스트") || ($0.kind == .booster && $0.cards.count < 40) })  // 미니 팩은 뺀다(듀얼리스트 팩은 30장부터)
        #expect(db.packs.allSatisfy { $0.date < "2026-10-14" })
        // 정규 부스터끼리는 날짜순, 시대마다 그 시대 팩만 있고 정규 부스터 뒤에 듀얼리스트 팩
        let boosterDates = db.packs.filter { $0.kind == .booster }.map(\.date)
        #expect(boosterDates == boosterDates.sorted())
        for era in db.eras {
            let kinds = db.packs[era.packs].map(\.kind)
            #expect(db.packs[era.packs].allSatisfy { $0.era == era.name } && !zip(kinds, kinds.dropFirst()).contains { $0 == .duelist && $1 == .booster }, "\(era.name)")
        }
        #expect(db.packs.first?.setCode == "LOB")
        #expect(db.eras.map(\.name) == ["DM", "GX", "5D's", "ZEXAL", "ARC-V", "VRAINS", "Modern"])
        let kinds = Dictionary(grouping: db.cards.values, by: \.kind).mapValues(\.count)
        #expect(kinds == [.monster: 5470, .spell: 1892, .trap: 1524])  // 새 카드 580종 = 몬스터 333·마법 154·함정 93
        #expect(db.cards.values.filter { $0.field == true }.count == 204 &&  /* 새 필드 마법 11종 */ db.cards.values.allSatisfy { $0.field != true || $0.kind == .spell })
        // 정규 부스터는 노멀 몬스터가 보장 장 수 이상이라(실측 최소 12장, 파괴자의 힘) 몬스터 슬롯이 다른 티어로 올라가지 않는다
        let normalMonsters = { (p: Pack) in p.cards.filter { db.tier($0) == 1 && db.cards[$0]?.kind == .monster }.count }
        #expect(db.packs.filter { $0.kind == .booster }.allSatisfy { normalMonsters($0) >= Balance.monstersPerPack })
        // 어느 팩이든 몬스터(등급 무관)가 보장 장 수 이상이라 몬스터 슬롯은 늘 채워진다
        #expect(db.packs.allSatisfy { p in p.cards.filter { db.cards[$0]?.kind == .monster }.count >= Balance.monstersPerPack })
        // 노멀 몬스터가 모자란 팩은 헬카이저 편·주다이 편 3뿐(각 1장, 재수록으로 등급이 오름): 둘째 몬스터 칸은 R 몬스터로 올라간다
        #expect(Set(db.packs.filter { normalMonsters($0) < Balance.monstersPerPack }.map(\.pid)) == ["78803001", "78803004"])
        // 시대별 정규 11·16·16·8·12·12·26 + 듀얼리스트 3·7·4·4·0·6·6
        #expect(db.eras.map(\.packs) == [0..<14, 14..<37, 37..<57, 57..<69, 69..<81, 81..<99, 99..<131])
        // 시대 첫 팩: 듀얼리스트의 투혼(GX), 듀얼리스트의 태동(싱크로), 리턴 오브 더 듀얼리스트(엑시즈), 더 듀얼리스트 어드벤트(펜듈럼), 코드 오브 더 듀얼리스트(링크), 라이즈 오브 더 듀얼리스트(Modern)
        #expect(db.eras.map { db.packs[$0.packs.lowerBound].setCode } == ["LOB", "SOD", "TDGS", "REDU", "DUEA", "COTD", "ROTD"])
        #expect(db.packs.allSatisfy { $0.setCode != nil && $0.imageURL != nil })
        // 한글판 표지, 한국 표지가 없는 만죠메 편만 일본판
        #expect(db.packs.allSatisfy { $0.kind == .duelist && $0.pid == "78802001" ? $0.imageURL!.contains("BoosterJP") : $0.imageURL!.contains("BoosterKR") })
        #expect(db.allCIDs.count == 8886)  // 8306 + 듀얼리스트 팩에만 있는 578종 + 듀얼리스트 팩 소재로 새로 넣은 팩 밖 융합 1종(인페리온 매그넘)·소재 1종(마그넷 벨세리온)
        // 재수록 카드는 수록 팩 중 가장 높은 등급: 유벨(환영의 어둠 N, 팬텀 나이트메어 QCSE → SE)
        #expect(db.cards.values.first { $0.name == "유벨" }?.rarity == "SE")
        #expect(db.cards.values.first { $0.name == "붉은 눈의 흑룡" }?.rarity == "SE")  // 푸른 눈의 백룡의 전설 UR → 배틀 시티 편·레전드듀얼리스트 편 SE
        // 여러 팩에 든 카드: 붉은 눈의 흑룡 4088(푸른 눈의 백룡의 전설·배틀 시티 편·레전드듀얼리스트 편)
        let redEyesPacks = db.packs.filter { $0.cards.contains(4088) }
        #expect(redEyesPacks.count == 3 && redEyesPacks.contains { $0.kind == .duelist })
        // 넣은 카드는 우리 팩 중 가장 높은 등급이라 듀얼리스트 팩 레어도로 내려갈 수 있다: 궁극의 푸른 눈의 백룡(첫 수록 UR → 파라오의 기억 편 R)
        #expect(db.cards[4386]?.rarity == "R")
        // 듀얼리스트 팩 카드 + 등급이 오른 기존 22종 − 듀얼리스트 팩 등급이 첫 수록판보다 낮은 넣은 카드 4종(카오스 솔저 등)
        let tiers = Dictionary(grouping: db.cards.values, by: \.tier).mapValues(\.count)
        #expect(tiers == [1: 4975, 2: 1932, 3: 1021, 4: 582, 5: 376])
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
        #expect(db.cards.values.filter { $0.matches(kind: "fusion") }.count == 353)  // 듀얼리스트 팩 융합 26종 + 인페리온 매그넘
        // 융합 소재(build-cards.py 가 효과 첫 줄에서 뗀다): 마스크드 히어로 10종·NEX 2종·베어트론 빼고 340종(새 융합 27종 모두 소재 있음), 전부 카드인 건 122종
        let fusions = db.cards.values.filter { $0.matches(kind: "fusion") }
        #expect(fusions.filter { $0.materials != nil }.count == 340)
        #expect(fusions.filter { $0.materials?.allSatisfy { $0.cid != nil } == true }.count == 122)
        #expect(db.cards[20769]?.materials?.first == Material(rule: "\"엘리멘틀 히어로 페더맨\"이나 \"엘리멘틀 히어로 버스트 레이디\""))  // "A"이나 "B" 는 조건
        #expect(db.cards[4043]?.materials == [Material(cid: 4044), Material(cid: 4045)] && db.cards[4043]?.text == "")  // 용기사 가이아: 바닐라라 효과가 빈다
        // 조건 없는 융합의 131팩에 없는 소재는 그 융합이 든 팩에 넣는다: 미노켄타우로스의 미노타우로스(스타터 덱 카드, 강철의 습격자)
        #expect(db.cards[4098]?.materials?.first == Material(cid: 4032) && db.packs[1].cards.contains(4032))
        // 131팩 밖 융합 중 조건 없고 팩 소재가 있는 것은 팩 소재가 처음 나온 팩 중 가장 늦은 팩에 넣는다: 합체마신－게이트 가디언(강철의 습격자)
        #expect(db.packs[1].cards.contains(18325) && db.cards[18325]?.materials == [Material(cid: 4377), Material(cid: 4378), Material(cid: 4379)])
        // 밖 소재도 같은 팩에: 극화염의 검사(화염의 검사 + 조건 융합 투의염참룡), 메테오 블랙 드래곤(붉은 눈의 흑룡 + 메테오 드래곤)
        #expect(db.cards[19727]?.materials == [Material(cid: 4021), Material(cid: 19728)] && [19727, 19728, 4719, 4718].allSatisfy(db.packs[0].cards.contains))
        #expect(db.cards[4121] == nil)  // 카오스 위저드: 소재 흑마족의 커튼이 한국 미발매
        // 마스크 체인지·마스크드 히어로 10종은 한국 첫 수록일 직전 정규 부스터에(듀얼리스트 팩이 앞에 끼어 인덱스가 밀린다): 마스크 체인지(익스트림 빅토리), 아토믹(듀얼리스트 어드밴스)
        #expect(db.packs.firstIndex { $0.cards.contains(CardDB.maskChange) } == 48 && db.cards[CardDB.maskChange]?.kind == .spell)
        #expect(db.packs.firstIndex { $0.cards.contains(21614) } == 119 && db.cards.values.filter { $0.mask == true }.count == 10)
        #expect(db.cards.values.filter { $0.hero == true }.count == 100 && db.fusionCIDs.count == 331)  // 듀얼리스트 팩 HERO 9종, 만들 수 있는 융합 24종 추가
        // 조건이 섞인 융합의 101팩 밖 소재도 그 융합의 팩에 넣어서 이름만 남은 소재가 없다: 지천의 기사 가이아드레이크의 대지의 기사 가이아 나이트(폭풍의 스타스트라이크)
        #expect(db.cards.values.allSatisfy { $0.materials?.allSatisfy { $0.name == nil } ?? true })
        #expect(db.cards[9116]?.materials?.first == Material(cid: 7697) && db.packs[46].cards.contains(7697))  // 듀얼리스트 팩 10개가 앞에 끼어 36 → 46
        #expect(fusions.allSatisfy { !$0.text.contains("＋") })
        // 만들 수 있는 융합 331종(새 융합 27종 중 조건을 못 읽는 키메라테크 램페이지·선라이저·유니온 컨트롤러 빼고 24종 추가)은 소재 줄마다 맞는 카드 목록(picks)이 있다: 투의염참룡(자기 빼고 드래곤족 + 전사족 / 화염 속성)
        #expect(db.cards.values.filter { $0.picks != nil }.count == 331)
        #expect(db.cards[12777]?.picks?.first?.any.contains(6315) == true)  // 앤틱 기어 데블의 "앤틱 기어" 몬스터에 앤틱 기어 골렘
        #expect(db.cards[4043]?.picks == [Pick(any: [4044]), Pick(any: [4045])] && db.cards[21614]?.picks?.first?.any.count == 10)  // 용기사 가이아(카드 소재), 마스크드 히어로 아토믹(화염 HERO, 듀얼리스트 팩으로 1종 늘어 10)
        #expect(db.cards[19728]?.picks?.map(\.any.count) == [465, 81] /* 듀얼리스트 팩 드래곤족·화염 전사족만큼 늘어남 */ && db.cards[19728]?.picks?[0].any.contains(4007) == true)
        #expect(db.cards[12953]?.picks?.map { $0.join == true } == [false, true, true, true])  // 패왕룡 즈아크: 종류마다 1장씩
        // 「융합」 마법은 첫 팩에 있어서 어느 시대 범위에서도 구할 수 있다
        #expect(db.cards[CardDB.fusionSpell].map { ($0.name, $0.kind) } ?? ("", .monster) == ("융합", .spell))
        #expect(db.packs[0].cards.contains(CardDB.fusionSpell))
        #expect(db.materialNeed[6390] == 3 && db.materialNeed[4007] == 3)  // 사이버 드래곤(사이버 엔드 드래곤), 푸른 눈의 백룡(궁극의 푸른 눈의 백룡)
        #expect(db.prefix(packs: 14).materialNeed[6390] == nil)  // DM 범위엔 사이버 드래곤을 쓰는 융합이 없다
        // 넣은 융합 5장(스팀 힐러 등)·소재 2장은 듀얼리스트 팩에 원래 있어 정규 부스터에 끼워 넣지 않는다
        #expect(db.packs.filter { $0.cards.contains(6535) }.allSatisfy { $0.kind == .duelist })  // 엘리멘틀 히어로 스팀 힐러(주다이 편)
        #expect(db.packs.filter { $0.cards.contains(4370) }.map(\.pid) == ["78804003", "78811002"])  // 카오스 솔저: 유희 편·배틀 시티 편만
        // 버블맨은 주다이 편에 원래 있어 팩 소재가 되고(절대원소의 힘·정의의 적에 더는 안 넣는다) 한 팩에만 있다
        #expect(db.packs.filter { $0.cards.contains(6393) }.count == 1)
        // 시대 범위: 기본 GX 는 GX 듀얼리스트 팩 7개까지, DM 은 유희 편(2009)까지라 그 카드가 무료 카드 풀(allCIDs)에 든다
        let gx = Game(db: db, state: GameState()).db
        #expect(gx.packs.count == 37 && gx.packs.filter { $0.era == "GX" && $0.kind == .duelist }.count == 7 && gx.packIndex("78804004") == nil)  // 유성 편은 밖
        var dmState = GameState(); dmState.eraLimit = "DM"
        let dm = Game(db: db, state: dmState).db
        #expect(dm.packIndex("78804003") != nil && db.packs[db.packIndex("78804003")!].cards.allSatisfy(dm.cidSet.contains))
        // 언어 무관 코드: 마법·함정만 kind 가 있고, summons 는 몬스터에만, 시대 순 코드만
        #expect(db.cards.values.allSatisfy { [nil, "spell", "trap"].contains($0.kindCode) })
        #expect(db.cards.values.allSatisfy { $0.summons == nil || ($0.kind == .monster && $0.summons!.allSatisfy(CardInfo.summonCodes.contains)) })
        #expect(db.cards[11835]?.summons == ["xyz", "pendulum"])
        // 만들 수 있는 융합(융합 전용 후보)은 어느 시대 범위에서도 소재 줄마다 맞는 카드가 같은 범위 안에 있고(한 카드를 여러 장 모으면
        // 장 수는 채운다), 마스크드 히어로는 「마스크 체인지」도 있다 → Game.isFusionOnly 가 범위 검사를 안 한다
        for era in db.eras {
            let sub = db.prefix(packs: era.packs.upperBound)
            #expect(sub.allCIDs.allSatisfy { cid in
                guard let card = sub.cards[cid], let picks = card.picks else { return true }
                return picks.allSatisfy { !$0.any.isDisjoint(with: sub.cidSet) } && (card.mask != true || sub.cidSet.contains(CardDB.maskChange))
            }, "\(era.name)까지: 맞는 카드가 범위 밖인 융합 소재가 있음")
        }
    }
}

/// 이름순 키: Finder 순서(숫자는 크기순), 같은 이름은 같은 순위(그 안에서는 팩 순번으로 정렬된다)
@Test func nameRanksFollowFinderOrderAndTieEqualNames() {
    let r = CardDB.nameRanks([1: card("카드10"), 2: card("카드2"), 3: card("가"), 4: card("카드2")])
    #expect(r[3]! < r[2]! && r[2]! < r[1]!)
    #expect(r[2] == r[4])
}

/// cards_XX.json 에 범위 밖 등급이 있어도 1~5 로 잘라 읽는다 (Pull.label 등이 죽지 않게)
@Test func outOfRangeTiersAreClamped() {
    let db = CardDB(packs: [], cards: [1: card(tier: 0), 2: card(tier: 9), 3: card(tier: 3)])
    #expect([1, 2, 3].map(db.tier) == [1, 5, 3])
    #expect(Pull(cid: 2, tier: db.tier(2), isNew: true).label == "SE")
}

/// 언어별 카드 파일 이름: ko → KO, ja → JP, en → EN (모르는 언어는 EN)
@Test func cardFileNamePerLanguage() {
    #expect(["ko", "ja", "en", "fr"].map(CardDB.fileName) == ["cards_KO", "cards_JP", "cards_EN", "cards_EN"])
    #expect(CardDB.repoURL("ko").lastPathComponent == "cards_KO.json")
}
