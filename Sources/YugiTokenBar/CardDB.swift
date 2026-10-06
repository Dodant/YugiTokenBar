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

    static let rarities = ["N", "R", "SR", "UR", "SE"]
    var rarity: String { Self.rarities[min(max(tier, 1), Self.rarities.count) - 1] }

    /// level 칸의 이름: 엑시즈는 랭크, 링크는 링크 수
    var levelName: String { type?.contains("엑시즈") == true ? "랭크" : type?.contains("링크") == true ? "링크" : "레벨" }

    /// 마법·함정은 attr 칸에 "마법"·"함정"이 들어 있고, 나머지(속성)는 몬스터.
    var kind: CardKind { attr.flatMap(CardKind.init(rawValue:)) ?? .monster }

    /// 컬렉션 종류 메뉴의 소환법 (시대 순)
    static let summons = ["의식", "융합", "싱크로", "엑시즈", "펜듈럼", "링크"]
    /// 종류 메뉴 값과 맞는지: 몬스터·마법·함정은 kind, 소환법은 몬스터의 type 칸 (의식 마법은 아님, 엑시즈 펜듈럼은 둘 다)
    func matches(kind filter: String) -> Bool {
        kind.rawValue == filter || (kind == .monster && type?.components(separatedBy: "/").contains(filter) == true)
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
}

/// 카드 종류. rawValue 는 컬렉션 종류 메뉴 값이자 cards.json attr 칸 값(마법·함정).
enum CardKind: String, CaseIterable, Sendable {
    case monster = "몬스터", spell = "마법", trap = "함정"
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

/// cards.json (tools/build-cards.py 산출물). packs 는 발매일 오름차순.
struct CardDB: Sendable {
    private(set) var packs: [Pack]
    let cards: [Int: CardInfo]
    private(set) var allCIDs: [Int]
    /// allCIDs 를 빠르게 찾기 위한 집합 (시대 범위 안인지)
    private(set) var cidSet: Set<Int>
    /// 범위 안 융합 몬스터의 소재로 필요한 최대 장 수 (사이버 드래곤 → 3, 사이버 엔드 드래곤). 중복 판매에서 그만큼 남긴다.
    private(set) var materialNeed: [Int: Int]

    /// 등급은 1~5 로 자른다. cards.json 에 범위 밖 등급이 있어도 뽑기(티어 1~5 만 찾음)·판매가·등급 표시가 어긋나거나 죽지 않게.
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

    /// 앞 n 팩만 쓰는 DB (설정의 "시대 범위"). cards 는 그대로 두어 범위 밖 보유·기록 카드도 이름·이미지를 찾는다.
    func prefix(packs n: Int) -> CardDB {
        var db = self
        db.packs = Array(packs.prefix(n))
        db.cidSet = Set(db.packs.flatMap(\.cards))
        db.allCIDs = db.cidSet.sorted()
        db.materialNeed = Self.materialNeeds(db.allCIDs, cards)
        return db
    }

    /// 시대별 첫 팩(발매순 인덱스): DM 푸른 눈의 백룡의 전설, GX 듀얼리스트의 투혼, 5D's 듀얼리스트의 태동(싱크로),
    /// ZEXAL 리턴 오브 더 듀얼리스트(엑시즈), ARC-V 더 듀얼리스트 어드벤트(펜듈럼), VRAINS 코드 오브 더 듀얼리스트(링크),
    /// Modern 라이즈 오브 더 듀얼리스트(VRAINS 이후).
    // ponytail: 팩 목록이 고정(cards.json)이라 인덱스로 나눈다. 팩을 더 넣으면 여기도 고친다.
    static let eraStarts = [("DM", 0), ("GX", 11), ("5D's", 27), ("ZEXAL", 43), ("ARC-V", 51), ("VRAINS", 63), ("Modern", 75)]
    /// 「융합」 마법 카드 (푸른 눈의 백룡의 전설 SR). 1장 이상 있어야 융합할 수 있고 소비되지 않는다.
    static let fusionSpell = 4837
    /// 「날개 크리보」(잃어버린 천년 SR). 가지면 파트너가 해금된다.
    static let partnerCard = 6314
    /// 시대를 대표하는 소환법 (설정의 시대 범위 메뉴 표시용)
    static let eraSummons = ["DM": "의식", "GX": "융합", "5D's": "싱크로", "ZEXAL": "엑시즈", "ARC-V": "펜듈럼", "VRAINS": "링크", "Modern": "지원"]

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

    /// .app 안에서는 Contents/Resources/cards.json, `swift run`·테스트에서는 저장소의 Resources/cards.json.
    static func bundled() throws -> CardDB {
        if let url = Bundle.main.url(forResource: "cards", withExtension: "json") {
            return try load(from: url)
        }
        return try load(from: repoCardsURL)
    }

    static let repoCardsURL = AppInfo.repoRoot.appendingPathComponent("Resources/cards.json")
}
