import Foundation

struct CardInfo: Codable, Sendable, Equatable {
    let name: String
    let attr: String?
    let level: Int?
    let type: String?
    let atk: String?
    let def: String?
    let text: String
    let imageId: Int?
    /// 1 N · 2 R · 3 SR · 4 UR · 5 SE. 재수록 카드는 수록 팩 중 가장 높은 등급 (build-cards.py 가 옮겨 둔 것).
    var tier: Int = 1
    /// 펜듈럼 몬스터만: P스케일과 펜듈럼 효과
    var scale: Int? = nil
    var pendulum: String? = nil
    /// 융합 몬스터만: 효과 첫 줄(소재 줄)을 build-cards.py 가 떼어 둔 것. NEX 로만 소환하는 2종은 없다.
    var materials: [Material]? = nil

    /// 언어와 상관없는 종류 코드(JSON "kind"): 마법 "spell"·함정 "trap", 몬스터는 nil. build-cards.py 가 KO attr 로 정한다
    var kindCode: String? = nil
    /// 몬스터의 소환법 코드(시대 순, CardInfo.summonCodes 중). build-cards.py 가 KO type 으로 정한다
    var summons: [String]? = nil
    /// "HERO" 몬스터 (마스크 체인지의 소재). build-cards.py 가 KO 이름으로 정한다
    var hero: Bool? = nil
    /// 「마스크 체인지」로만 소환하는 마스크드 히어로: 같은 속성 hero 몬스터 1장으로 만든다
    var mask: Bool? = nil

    enum CodingKeys: String, CodingKey {
        case name, attr, level, type, atk, def, text, imageId, tier, scale, pendulum, materials, summons, hero, mask
        case kindCode = "kind"
    }

    static let rarities = ["N", "R", "SR", "UR", "SE"]
    var rarity: String { Self.rarities[min(max(tier, 1), Self.rarities.count) - 1] }

    /// level 칸의 뜻: 엑시즈는 랭크, 링크는 링크 수
    enum LevelKind { case level, rank, link }
    var levelKind: LevelKind { summons?.contains("xyz") == true ? .rank : summons?.contains("link") == true ? .link : .level }

    var kind: CardKind { kindCode.flatMap(CardKind.init(rawValue:)) ?? .monster }

    /// 컬렉션 종류 메뉴의 소환법 코드 (시대 순)
    static let summonCodes = ["ritual", "fusion", "synchro", "xyz", "pendulum", "link"]
    /// 소환법·시대 대표 코드의 화면 이름
    static func summonTitle(_ code: String) -> String {
        switch code {
        case "ritual": String(localized: "의식")
        case "fusion": String(localized: "융합")
        case "synchro": String(localized: "싱크로")
        case "xyz": String(localized: "엑시즈")
        case "pendulum": String(localized: "펜듈럼")
        case "link": String(localized: "링크")
        case "support": String(localized: "지원")
        default: code
        }
    }
    /// 종류 메뉴 값과 맞는지: 몬스터·마법·함정은 kind, 소환법은 몬스터의 summons (의식 마법은 아님, 엑시즈 펜듈럼은 둘 다)
    func matches(kind filter: String) -> Bool {
        kind.rawValue == filter || (kind == .monster && summons?.contains(filter) == true)
    }

    /// 융합에 쓸 소재 (cid → 장 수). 소재가 전부 100팩 카드인 융합 몬스터만, 조건이나 없는 카드가 섞이면 nil.
    var fusionMaterials: [Int: Int]? {
        guard let materials else { return nil }
        var need: [Int: Int] = [:]
        for m in materials {
            guard let cid = m.cid else { return nil }
            need[cid, default: 0] += m.count ?? 1
        }
        return need
    }

    /// 융합(소재를 다 아는 융합 몬스터)이나 마스크 체인지로 만들 수 있는 카드
    var craftable: Bool { fusionMaterials != nil || mask == true }
}

/// 카드 종류. rawValue 는 컬렉션 종류 메뉴 값이자 cards_XX.json "kind" 값(마법·함정, 몬스터는 생략).
enum CardKind: String, CaseIterable, Sendable {
    case monster, spell, trap

    var title: String {
        switch self {
        case .monster: String(localized: "몬스터")
        case .spell: String(localized: "마법")
        case .trap: String(localized: "함정")
        }
    }
}

/// 융합 소재 하나: cid 는 100팩의 카드, name 은 100팩에 없는 카드, rule 은 "전사족 몬스터" 같은 조건. count 는 "× N".
struct Material: Codable, Sendable, Equatable {
    var cid: Int? = nil
    var name: String? = nil
    var rule: String? = nil
    var count: Int? = nil
}

struct Pack: Codable, Sendable, Identifiable, Equatable {
    let pid: String
    let name: String
    let date: String
    /// 수록 카드 cid (등급은 CardInfo.tier)
    var cards: [Int]
    /// 대응하는 TCG 팩 코드 (LOB 등)
    var setCode: String? = nil
    /// 봉투 이미지: Yugipedia 한글판, 없으면 YGOPRODeck 영문판
    var imageURL: String? = nil
    var id: String { pid }
}

/// cards_XX.json (tools/build-cards.py 산출물). packs 는 발매일 오름차순.
struct CardDB: Sendable {
    private(set) var packs: [Pack]
    let cards: [Int: CardInfo]
    private(set) var allCIDs: [Int]
    /// allCIDs 를 빠르게 찾기 위한 집합 (시대 범위 안인지)
    private(set) var cidSet: Set<Int>
    /// 범위 안 융합 몬스터의 소재로 필요한 최대 장 수 (사이버 드래곤 → 3, 사이버 엔드 드래곤). 중복 판매에서 그만큼 남긴다.
    private(set) var materialNeed: [Int: Int]
    /// 범위 안 융합 몬스터(소재를 아는 카드·마스크드 히어로) 수. 설정 화면이 그릴 때마다 세지 않게 미리 센다.
    private(set) var fusionCount: Int
    /// 만들 수 있는 카드 전체: 소재를 다 아는 융합 몬스터·마스크드 히어로 (`fusionMaterials` 는 부를 때마다 사전을 만들어서, 상점이 그릴 때 쓰지 않게)
    let fusionCIDs: Set<Int>

    /// 등급은 1~5 로 자른다. cards_XX.json 에 범위 밖 등급이 있어도 뽑기(티어 1~5 만 찾음)·판매가·등급 표시가 어긋나거나 죽지 않게.
    init(packs: [Pack], cards: [Int: CardInfo]) {
        self.packs = packs
        let cards = cards.mapValues { card in
            var card = card
            card.tier = min(max(card.tier, 1), CardInfo.rarities.count)
            return card
        }
        self.cards = cards
        self.allCIDs = cards.keys.sorted()
        self.cidSet = Set(cards.keys)
        self.materialNeed = Self.materialNeeds(allCIDs, cards)
        self.fusionCount = Self.fusionCount(allCIDs, cards)
        self.fusionCIDs = Set(cards.keys.filter { cards[$0]?.craftable == true })
    }

    /// 컬렉션 이름순 정렬 키: cid → 이름 순위(Finder 순서, 같은 이름은 같은 순위). 정렬마다 문자열을 비교하지 않으려고 쓴다
    static func nameRanks(_ cards: [Int: CardInfo]) -> [Int: Int] {
        let sorted = cards.sorted { $0.value.name.localizedStandardCompare($1.value.name) == .orderedAscending }
        var ranks: [Int: Int] = [:], rank = 0
        for (i, (cid, info)) in sorted.enumerated() {
            if i > 0, sorted[i - 1].value.name.localizedStandardCompare(info.name) != .orderedSame { rank += 1 }
            ranks[cid] = rank
        }
        return ranks
    }

    func tier(_ cid: Int) -> Int { cards[cid]?.tier ?? 1 }

    private static func materialNeeds(_ cids: [Int], _ cards: [Int: CardInfo]) -> [Int: Int] {
        cids.reduce(into: [:]) { need, cid in
            for (m, n) in cards[cid]?.fusionMaterials ?? [:] { need[m] = max(need[m] ?? 0, n) }
        }
    }

    private static func fusionCount(_ cids: [Int], _ cards: [Int: CardInfo]) -> Int {
        cids.filter { cards[$0]?.craftable == true }.count
    }

    /// 앞 n 팩만 쓰는 DB (설정의 "시대 범위"). cards 는 그대로 두어 범위 밖 보유·기록 카드도 이름·이미지를 찾는다.
    func prefix(packs n: Int) -> CardDB {
        var db = self
        db.packs = Array(packs.prefix(n))
        db.cidSet = Set(db.packs.flatMap(\.cards))
        db.allCIDs = db.cidSet.sorted()
        db.materialNeed = Self.materialNeeds(db.allCIDs, cards)
        db.fusionCount = Self.fusionCount(db.allCIDs, cards)
        return db
    }

    /// 시대별 첫 팩(발매순 인덱스): DM 푸른 눈의 백룡의 전설, GX 듀얼리스트의 투혼, 5D's 듀얼리스트의 태동(싱크로),
    /// ZEXAL 리턴 오브 더 듀얼리스트(엑시즈), ARC-V 더 듀얼리스트 어드벤트(펜듈럼), VRAINS 코드 오브 더 듀얼리스트(링크),
    /// Modern 라이즈 오브 더 듀얼리스트(VRAINS 이후).
    // ponytail: 팩 목록이 고정(cards_XX.json)이라 인덱스로 나눈다. 팩을 더 넣으면 여기도 고친다.
    static let eraStarts = [("DM", 0), ("GX", 11), ("5D's", 27), ("ZEXAL", 43), ("ARC-V", 51), ("VRAINS", 63), ("Modern", 75)]
    /// 「융합」 마법 카드 (푸른 눈의 백룡의 전설 SR). 1장 이상 있어야 융합할 수 있고 소비되지 않는다.
    static let fusionSpell = 4837
    /// 「마스크 체인지」(익스트림 빅토리에 넣은 프리미엄 팩 Vol.6 SE). 1장 이상 있어야 마스크드 히어로를 만들 수 있고 소비되지 않는다.
    static let maskChange = 9066
    /// 「날개 크리보」(잃어버린 천년 SR). 가지면 파트너가 해금된다.
    static let partnerCard = 6314
    /// 시대를 대표하는 소환법 코드 (설정의 시대 범위 메뉴 표시용, 이름은 CardInfo.summonTitle)
    static let eraSummons = ["DM": "ritual", "GX": "fusion", "5D's": "synchro", "ZEXAL": "xyz", "ARC-V": "pendulum", "VRAINS": "link", "Modern": "support"]

    /// (시대 이름, 팩 인덱스 범위). 테스트용 작은 DB 에선 빈 시대를 뺀다.
    var eras: [(name: String, packs: Range<Int>)] {
        Self.eraStarts.indices.map { i in
            let start = min(Self.eraStarts[i].1, packs.count)
            let end = i + 1 < Self.eraStarts.count ? min(Self.eraStarts[i + 1].1, packs.count) : packs.count
            return (Self.eraStarts[i].0, start..<end)
        }.filter { !$0.packs.isEmpty }
    }

    static func load(from url: URL) throws -> CardDB {
        struct File: Decodable {
            let packs: [Pack]
            let cards: [String: CardInfo]
        }
        let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
        var cards: [Int: CardInfo] = [:]
        for (key, info) in file.cards {
            if let cid = Int(key) { cards[cid] = info }
        }
        return CardDB(packs: file.packs, cards: cards)
    }

    /// 언어별 카드 파일 이름(확장자 없음): ko → cards_KO, ja → cards_JP, 그 밖 → cards_EN
    static func fileName(_ lang: String) -> String { "cards_" + (["ko": "KO", "ja": "JP"][lang] ?? "EN") }

    /// .app 안에서는 Contents/Resources/cards_XX.json, `swift run`·테스트에서는 저장소의 Resources/cards_XX.json.
    static func bundled(lang: String = AppLanguage.current) throws -> CardDB {
        if let url = Bundle.main.url(forResource: fileName(lang), withExtension: "json") {
            return try load(from: url)
        }
        return try load(from: repoURL(lang))
    }

    static func repoURL(_ lang: String) -> URL {
        AppInfo.repoRoot.appendingPathComponent("Resources/\(fileName(lang)).json")
    }
}
