import Foundation

/// 그리드 한 칸. id 는 위치가 아니라 카드(cid)라 목록이 바뀌어도 칸 뷰가 다른 카드로 재사용되지 않는다 (한 목록 안 cid 는 유일).
/// number 는 등급 필터·정렬과 상관없이 팩(또는 전체) 안 순번으로, 같은 값일 때 정렬 기준으로만 쓴다.
struct DexEntry: Identifiable {
    let number: Int
    let cid: Int
    let label: String
    var id: Int { cid }
}

/// 사이드바 선택: 전체 · 즐겨찾기 · 최근 획득 · 팩 · 덱
enum DexScope: Hashable {
    case all, favorites, recent
    case pack(Int)
    case deck(UUID)

    /// UserDefaults 저장용: "all", "favorites", "recent", "pack:3", "deck:<UUID>"
    var key: String {
        switch self {
        case .all: "all"
        case .favorites: "favorites"
        case .recent: "recent"
        case .pack(let i): "pack:\(i)"
        case .deck(let id): "deck:\(id.uuidString)"
        }
    }

    init?(key: String) {
        let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
        switch (parts.first, parts.count) {
        case ("all", 1): self = .all
        case ("favorites", 1): self = .favorites
        case ("recent", 1): self = .recent
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
    /// 0 = 모든 등급, 1~5 = CardInfo.tier, `overframeTier` = 오버프레임 판이 있는 카드만
    var tier = 0
    static let overframeTier = -1
    /// "" = 모든 종류, 아니면 CardKind.rawValue 또는 소환법 코드 (CardInfo.matches)
    var kind = ""
    /// 띄어쓰기를 뺀 검색어 ("푸른눈" 으로도 "푸른 눈의 백룡" 이 찾아진다)
    var search = ""
    var showUnowned = true
    var sort = DexSort.pack
    var era = ""
    /// 결과에 영향을 줄 때만 채운다: 보유(미보유 숨기기·보유 많은 순), 즐겨찾기(즐겨찾기 범위), 획득 기록(최근 획득 범위), 덱 카드(덱 범위)
    var owned: [Int: Int]?
    var favorites: Set<Int>?
    var recent: [Int]?
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
        // 최근 획득: 획득 기록(최근 50장) 최신순, 같은 카드는 한 번, 시대 범위 안만
        case .recent?:
            { let inRange = Set(all()); var once = Set<Int>()
              return game.state.log.map(\.cid).filter { inRange.contains($0) && once.insert($0).inserted } }()
        case .deck(let id)?:
            { let inDeck = game.deck(id)?.cards ?? [:]; return all().filter { inDeck[$0] != nil } }()
        default: all()
        }
        let needle = Self.squash(search)
        let tiered = cards.enumerated()
            .filter { tier == 0 || (tier == Self.overframeTier ? game.hasOverframe($0.element) : db.tier($0.element) == tier) }
            .filter { kind.isEmpty || db.cards[$0.element]?.matches(kind: kind) == true }
            .filter { search.isEmpty || Self.squash(db.cards[$0.element]?.name ?? "").localizedStandardContains(needle) }
            .map { DexEntry(number: $0.offset + 1, cid: $0.element, label: db.cards[$0.element]?.rarity ?? "N") }
        let list = tiered.filter { showUnowned || game.copies($0.cid) > 0 }
        guard sort != .pack else { return (tiered, list) }  // 이미 팩 순번 순 (최근 획득은 획득 순서)
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

/// game 에서 센 값을 보유·융합 설정·시대가 같은 동안 다시 세지 않는다 (사이드바 통계·"융합 가능" 목록).
/// 클래스라 채워도 뷰를 다시 그리지 않는다 (DexListCache 와 같은 이유).
@MainActor final class GameMemo<Value> {
    private let compute: (Game) -> Value
    private var key: (owned: [Int: Int], overframes: Set<Int>, fusionOnly: Bool, era: String)?
    private var value: Value?

    init(_ compute: @escaping (Game) -> Value) { self.compute = compute }

    func callAsFunction(_ game: Game) -> Value {
        let s = game.state
        if let key, let value, key.owned == s.owned, key.overframes == s.overframes, key.fusionOnly == s.fusionOnly, key.era == s.eraLimit { return value }
        let next = compute(game)
        key = (s.owned, s.overframes, s.fusionOnly, s.eraLimit)
        value = next
        return next
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
