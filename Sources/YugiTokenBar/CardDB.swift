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
    /// 1 N · 2 R · 3 SR · 4 UR · 5 SE/UL/HR
    let tier: Int
    let label: String
}

struct Pack: Codable, Sendable, Identifiable, Equatable {
    let pid: String
    let name: String
    let date: String
    let cards: [PackCard]
    var id: String { pid }
}

/// cards.json (tools/build-cards.py 산출물). packs 는 발매일 오름차순 = 해금 순서.
struct CardDB: Sendable {
    let packs: [Pack]
    let cards: [Int: CardInfo]
    let allCIDs: [Int]

    init(packs: [Pack], cards: [Int: CardInfo]) {
        self.packs = packs
        self.cards = cards
        self.allCIDs = cards.keys.sorted()
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

    static let repoCardsURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // Sources/YugiTokenBar
        .deletingLastPathComponent()  // Sources
        .deletingLastPathComponent()  // 저장소 루트
        .appendingPathComponent("Resources/cards.json")
}
