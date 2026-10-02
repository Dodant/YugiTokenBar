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
    /// 펜듈럼 몬스터만: P스케일과 펜듈럼 효과
    var scale: Int? = nil
    var pendulum: String? = nil

    /// level 칸의 이름: 엑시즈는 랭크, 링크는 링크 수
    var levelName: String { type?.contains("엑시즈") == true ? "랭크" : type?.contains("링크") == true ? "링크" : "레벨" }

    /// 몬스터 / 마법 / 함정. 마법·함정은 attr 칸에 "마법"·"함정"이 들어 있다.
    var kind: String { attr == "마법" || attr == "함정" ? attr! : "몬스터" }
}

struct PackCard: Codable, Sendable, Equatable {
    let cid: Int
    /// 1 N · 2 R · 3 SR · 4 UR (마스터 듀얼식 4등급)
    let tier: Int
    let label: String

    static let labels = ["N", "R", "SR", "UR"]

    /// cards.json 의 Konami 원래 레어도(SE·UL·HR = 티어 5)를 UR 로 합친다.
    var simplified: PackCard {
        let t = min(max(tier, 1), 4)
        return PackCard(cid: cid, tier: t, label: Self.labels[t - 1])
    }
}

struct Pack: Codable, Sendable, Identifiable, Equatable {
    let pid: String
    let name: String
    let date: String
    var cards: [PackCard]
    /// 대응하는 TCG 팩 코드 (LOB 등)
    var setCode: String? = nil
    /// 봉투 이미지: Yugipedia 한글판, 없으면 YGOPRODeck 영문판
    var imageURL: String? = nil
    var id: String { pid }
}

/// cards.json (tools/build-cards.py 산출물). packs 는 발매일 오름차순.
struct CardDB: Sendable {
    let packs: [Pack]
    let cards: [Int: CardInfo]
    let allCIDs: [Int]

    init(packs: [Pack], cards: [Int: CardInfo]) {
        self.packs = packs
        self.cards = cards
        self.allCIDs = cards.keys.sorted()
    }

    /// 시대별 첫 팩(발매순 인덱스): DM 푸른 눈의 백룡의 전설, GX 듀얼리스트의 투혼, 5D's 듀얼리스트의 태동(싱크로),
    /// ZEXAL 리턴 오브 더 듀얼리스트(엑시즈), ARC-V 더 듀얼리스트 어드벤트(펜듈럼), VRAINS 코드 오브 더 듀얼리스트(링크).
    // ponytail: 팩 목록이 고정(cards.json)이라 인덱스로 나눈다. 팩을 더 넣으면 여기도 고친다.
    static let eraStarts = [("DM", 0), ("GX", 11), ("5D's", 27), ("ZEXAL", 43), ("ARC-V", 51), ("VRAINS", 63)]

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
        var packs = file.packs
        for i in packs.indices { packs[i].cards = packs[i].cards.map(\.simplified) }
        return CardDB(packs: packs, cards: cards)
    }

    /// .app 안에서는 Contents/Resources/cards.json, `swift run`·테스트에서는 저장소의 Resources/cards.json.
    static func bundled() throws -> CardDB {
        if let url = Bundle.main.url(forResource: "cards", withExtension: "json") {
            return try load(from: url)
        }
        return try load(from: repoCardsURL)
    }

    static let repoCardsURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // Sources/YugiTokenBar
        .deletingLastPathComponent()  // Sources
        .deletingLastPathComponent()  // 저장소 루트
        .appendingPathComponent("Resources/cards.json")
}
