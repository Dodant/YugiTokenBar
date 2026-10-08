import Foundation

/// 그리드 한 칸. id 는 위치가 아니라 카드(cid)라 목록이 바뀌어도 칸 뷰가 다른 카드로 재사용되지 않는다 (한 목록 안 cid 는 유일).
/// number 는 등급 필터·정렬과 상관없이 팩(또는 전체) 안 순번으로, 같은 값일 때 정렬 기준으로만 쓴다.
struct DexEntry: Identifiable {
    let number: Int
    let cid: Int
    let label: String
    var id: Int { cid }
}

/// 사이드바 선택: 전체 · 즐겨찾기 · 팩 · 덱
enum DexScope: Hashable {
    case all, favorites
    case pack(Int)
    case deck(UUID)

    /// UserDefaults 저장용: "all", "favorites", "pack:3", "deck:<UUID>"
    var key: String {
        switch self {
        case .all: "all"
        case .favorites: "favorites"
        case .pack(let i): "pack:\(i)"
        case .deck(let id): "deck:\(id.uuidString)"
        }
    }

    init?(key: String) {
        let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
        switch (parts.first, parts.count) {
        case ("all", 1): self = .all
        case ("favorites", 1): self = .favorites
        case ("pack", 2): guard let i = Int(parts[1]) else { return nil }; self = .pack(i)
        case ("deck", 2): guard let id = UUID(uuidString: parts[1]) else { return nil }; self = .deck(id)
        default: return nil
        }
    }
}

enum DexSort: String, CaseIterable {
    case pack, tierDesc, tierAsc, name, copies

    var title: String {
        switch self {
        case .pack: String(localized: "팩 순서")
        case .tierDesc: String(localized: "높은 등급순")
        case .tierAsc: String(localized: "낮은 등급순")
        case .name: String(localized: "이름순")
        case .copies: String(localized: "보유 많은 순")
        }
    }
}

/// 그리드 목록을 정하는 조건. 같으면 결과도 같다.
struct DexQuery: Equatable {
    /// 검색 비교용: 공백과 가운뎃점(・)은 무시한다 ("ブラックマジシャン" 으로 "ブラック・マジシャン" 을 찾는다)
    static func squash(_ s: String) -> String { s.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "・", with: "") }
    var scope: DexScope?
    /// 0 = 모든 등급, 1~5 = CardInfo.tier
    var tier = 0
    /// "" = 모든 종류, 아니면 CardKind.rawValue 또는 소환법 코드 (CardInfo.matches)
    var kind = ""
    /// 띄어쓰기를 뺀 검색어 ("푸른눈" 으로도 "푸른 눈의 백룡" 이 찾아진다)
    var search = ""
    var showUnowned = true
    var sort = DexSort.pack
    var era = ""
    /// 결과에 영향을 줄 때만 채운다: 보유(미보유 숨기기·보유 많은 순), 즐겨찾기(즐겨찾기 범위), 덱 카드(덱 범위)
    var owned: [Int: Int]?
    var favorites: Set<Int>?
    var deck: Set<Int>?

    /// 카드 목록은 바뀌지 않으니 이름 순위는 처음 이름순으로 볼 때 한 번만 만든다 (비교마다 문자열을 대면 6천 장에 ~50ms)
    @MainActor private static var nameRank: [Int: Int] = [:]

    /// tiered: 범위·등급·종류·검색까지 거른 목록(부제의 보유 수용). visible: 그다음 미보유 숨기기 → 정렬, 같은 값이면 팩 순번 순.
    /// number 는 등급 필터·정렬과 상관없이 팩(또는 전체) 안 순번.
    @MainActor func entries(in game: Game) -> (tiered: [DexEntry], visible: [DexEntry]) {
        let db = game.db
        // 전체·즐겨찾기·덱: 팩 순서대로, 재수록은 처음 나온 팩 기준 한 번만
        var seen = Set<Int>()
        let all = { db.packs.flatMap(\.cards).filter { seen.insert($0).inserted } }
        let cards: [Int] = switch scope {
        case .pack(let i)? where db.packs.indices.contains(i): db.packs[i].cards
        case .favorites?: all().filter { game.state.favorites.contains($0) }
        case .deck(let id)?:
            { let inDeck = game.deck(id)?.cards ?? [:]; return all().filter { inDeck[$0] != nil } }()
        default: all()
        }
        let needle = Self.squash(search)
        let tiered = cards.enumerated()
            .filter { tier == 0 || db.tier($0.element) == tier }
            .filter { kind.isEmpty || db.cards[$0.element]?.matches(kind: kind) == true }
            .filter { search.isEmpty || Self.squash(db.cards[$0.element]?.name ?? "").localizedStandardContains(needle) }
            .map { DexEntry(number: $0.offset + 1, cid: $0.element, label: db.cards[$0.element]?.rarity ?? "N") }
        let list = tiered.filter { showUnowned || game.copies($0.cid) > 0 }
        guard sort != .pack else { return (tiered, list) }  // 이미 팩 순번 순
        let tierOf = { (e: DexEntry) in db.tier(e.cid) }
        if sort == .name, Self.nameRank.isEmpty { Self.nameRank = CardDB.nameRanks(db.cards) }
        let name = { (cid: Int) in Self.nameRank[cid] ?? .max }
        let visible = list.sorted { a, b in
            switch sort {
            case .pack: break
            case .tierDesc: if tierOf(a) != tierOf(b) { return tierOf(a) > tierOf(b) }
            case .tierAsc: if tierOf(a) != tierOf(b) { return tierOf(a) < tierOf(b) }
            case .name: if name(a.cid) != name(b.cid) { return name(a.cid) < name(b.cid) }
            case .copies: if game.copies(a.cid) != game.copies(b.cid) { return game.copies(a.cid) > game.copies(b.cid) }
            }
            return a.number < b.number
        }
        return (tiered, visible)
    }
}

/// 마지막 조건과 그 결과. 클래스라 채워도 뷰를 다시 그리지 않는다 (FrameStore 와 같은 이유).
@MainActor final class DexListCache {
    private var query: DexQuery?
    private var result: (tiered: [DexEntry], visible: [DexEntry]) = ([], [])

    func list(_ query: DexQuery, _ game: Game) -> (tiered: [DexEntry], visible: [DexEntry]) {
        if query != self.query { result = query.entries(in: game); self.query = query }
        return result
    }
}
