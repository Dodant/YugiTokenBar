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

    /// OCG Series 1~3 = 듀얼몬스터즈(DM), Series 4 부터(첫 팩 Soul of the Duelist) = GX 방영기 (Yugipedia 기준).
    static let firstGXSetCode = "SOD"

    /// (시대 이름, 팩 인덱스 범위) — 발매순이라 SOD 앞은 DM, 뒤는 GX.
    var eras: [(name: String, packs: Range<Int>)] {
        let gx = packs.firstIndex { $0.setCode == Self.firstGXSetCode } ?? packs.count
        return [("DM", 0..<gx), ("GX", gx..<packs.count)].filter { !$0.packs.isEmpty }
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
