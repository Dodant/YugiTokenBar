import Foundation

enum Balance {
    static let tokensPerCoin = 10_000
    static let packPrice = 1_000
    /// 코인으로 이만큼 사면 무료 팩 1장 (무료 팩으로 깐 건 세지 않는다)
    static let packsPerFreePack = 10
    static let tokensPerFreeCard = 10_000_000
    /// 팩 5번째 장의 티어 확률 (R / SR / UR / SE). SE 가 없는 팩은 UR 로 내려간다.
    static let slot5Weights: [(tier: Int, weight: Double)] = [(2, 0.70), (3, 0.18), (4, 0.10), (5, 0.02)]
    /// 무료 카드의 티어 확률 (N / R / SR / UR / SE). 티어 안에서는 균등.
    static let freeWeights: [(tier: Int, weight: Double)] = [(1, 0.60), (2, 0.25), (3, 0.10), (4, 0.04), (5, 0.01)]
    static let logLimit = 50
    /// 무료 카드를 한 번에 여는 최대 장 수 (팩 1봉투와 같은 5장)
    static let freeOpenBatch = 5
    /// 팩 1봉투에서 몬스터를 보장하는 장 수. 노멀 슬롯 앞에서부터 이만큼은 몬스터만 뽑는다 (모든 팩에 노멀 몬스터 13장 이상).
    static let monstersPerPack = 2
    /// 카드 1장 판매가 (티어 → 코인). 팩 기대 판매가 ≈ 206 < packPrice 라 사고팔기로 코인이 늘지 않는다.
    static let sellPrice: [Int: Int] = [1: 20, 2: 50, 3: 150, 4: 400, 5: 1_200]
    /// 덱에 같은 카드를 넣을 수 있는 최대 장 수 (유희왕 규칙)
    static let maxCopiesInDeck = 3
    /// 메인 덱 권장 장 수. 표시만 하고 강제하지 않는다.
    static let deckSize = 40...60
}

struct Pull: Sendable, Equatable {
    let cid: Int
    let tier: Int
    let isNew: Bool
    /// 중복 자동 판매로 바로 판 경우 받은 코인
    var soldFor: Int? = nil
    var label: String { CardInfo.rarities[tier - 1] }
}

struct Game: Sendable {
    /// 100팩 전체
    let fullDB: CardDB
    var state: GameState
    /// 시대 이름 → 그 시대까지 자른 DB (미리 만들어 두고 고르기만 한다)
    private let byEra: [String: CardDB]

    init(db: CardDB, state: GameState) {
        fullDB = db
        self.state = state
        byEra = Dictionary(uniqueKeysWithValues: db.eras.map { ($0.name, db.prefix(packs: $0.packs.upperBound)) })
    }

    /// 지금 시대 범위의 DB. 상점·컬렉션·뽑기 모두 이것만 본다.
    var db: CardDB { byEra[state.eraLimit] ?? fullDB }  // 모르는 이름이면 전체

    // MARK: 토큰 적립

    /// 오늘의 provider별 누적 토큰을 받아 늘어난 만큼만 적립한다. 원장은 같은 날 안에서 절대 내려가지 않는다
    /// (일시적으로 0이나 작은 값이 읽혀도 나중에 같은 토큰을 두 번 적립하지 않도록). 반환: 이번에 쌓인 무료 카드 장 수.
    @discardableResult
    mutating func claim(today: String, byProvider: [String: Int]) -> Int {
        guard state.claimedDate != nil else {
            // 첫 실행: 설치 전 사용량은 적립하지 않는다.
            state.claimedDate = today
            state.claimedByProvider = byProvider
            return 0
        }
        if let d = state.claimedDate, today < d { return 0 }  // 시계/시간대가 과거로 가도 원장을 리셋하지 않는다.
        if state.claimedDate != today {
            state.claimedDate = today
            state.claimedByProvider = [:]
        }
        var delta = 0
        for (provider, current) in byProvider {
            let claimed = state.claimedByProvider[provider] ?? 0
            if current > claimed {
                delta += current - claimed
                state.claimedByProvider[provider] = current
            }
        }
        return credit(delta)
    }

    /// 무료 카드는 바로 뽑지 않고 `pendingFree`에 쌓는다(사용자가 직접 연다). 반환: 이번에 쌓인 장 수.
    @discardableResult
    mutating func credit(_ tokens: Int) -> Int {
        guard tokens > 0 else { return 0 }
        state.coinRemainder += tokens
        state.coins += state.coinRemainder / Balance.tokensPerCoin
        state.coinRemainder %= Balance.tokensPerCoin
        state.dropProgress += tokens
        let n = state.dropProgress / Balance.tokensPerFreeCard
        state.dropProgress %= Balance.tokensPerFreeCard
        state.pendingFree += n
        return n
    }

    /// 쌓인 무료 카드를 최대 `freeOpenBatch`장 연다.
    mutating func openFree<R: RandomNumberGenerator>(using rng: inout R) -> [Pull] {
        var pulls: [Pull] = []
        while state.pendingFree > 0, pulls.count < Balance.freeOpenBatch {
            state.pendingFree -= 1
            guard let cid = drawFree(using: &rng) else { state.pendingFree = 0; break }
            let isNew = copies(cid) == 0
            give(cid, source: "free")
            pulls.append(Pull(cid: cid, tier: db.tier(cid), isNew: isNew, soldFor: autoSell(cid)))
        }
        return pulls
    }

    // MARK: 조회

    func copies(_ cid: Int) -> Int { state.owned[cid] ?? 0 }

    /// 시대 범위 안의 즐겨찾기 수 (사이드바 숫자 = 즐겨찾기 목록 장 수)
    var favoritesInRange: Int { state.favorites.filter { db.cidSet.contains($0) }.count }

    /// 시대 범위 안에서 1장 이상 가진 종류 수
    var ownedDistinct: Int { db.allCIDs.filter { copies($0) > 0 }.count }

    func progress(_ pack: Int) -> (owned: Int, total: Int) {
        let cards = db.packs[pack].cards
        return (cards.filter { copies($0) > 0 }.count, cards.count)
    }

    /// 팩의 모든 카드를 1장 이상 가졌으면 완료(✓ 표시만, 구매는 계속 가능).
    func isComplete(_ pack: Int) -> Bool {
        db.packs[pack].cards.allSatisfy { copies($0) > 0 }
    }

    func canBuy(_ pack: Int) -> Bool {
        state.coins >= Balance.packPrice
    }

    // MARK: 판매

    func sellPrice(_ cid: Int) -> Int {
        Balance.sellPrice[db.tier(cid)] ?? 0
    }

    /// 1장 판매. 보유하지 않았으면 nil, 팔았으면 받은 코인.
    mutating func sell(_ cid: Int) -> Int? {
        guard copies(cid) > 0 else { return nil }
        state.owned[cid] = copies(cid) == 1 ? nil : copies(cid) - 1
        let price = sellPrice(cid)
        state.coins += price
        return price
    }

    /// 중복분(`keep` 장 넘는 것)을 팔면 받을 (장 수, 코인). 각 카드 `keep` 장은 남는다.
    var duplicatesValue: (count: Int, coins: Int) {
        state.owned.filter { db.cidSet.contains($0.key) }.reduce((0, 0)) { acc, kv in
            let extra = kv.value - keep(kv.key)
            return extra > 0 ? (acc.0 + extra, acc.1 + extra * sellPrice(kv.key)) : acc
        }
    }

    /// 시대 범위 안 카드의 중복분을 모두 판다(범위 밖은 숨겨져 있으니 건드리지 않는다). 반환: 받은 코인.
    mutating func sellDuplicates() -> Int {
        var total = 0
        for (cid, n) in state.owned where n > keep(cid) && db.cidSet.contains(cid) {
            for _ in keep(cid)..<n { total += sell(cid) ?? 0 }
        }
        return total
    }

    // MARK: 파트너

    /// 「날개 크리보」를 가지고 있으면 파트너를 해금한다. 새로 해금했으면 true. 해금은 팔아도 유지된다.
    @discardableResult
    mutating func unlockPartnerIfOwned() -> Bool {
        guard !state.partnerUnlocked, copies(CardDB.partnerCard) > 0 else { return false }
        state.partnerUnlocked = true
        return true
    }

    // MARK: 덱

    func deck(_ id: UUID) -> Deck? { state.decks.first { $0.id == id } }

    /// 덱의 (보유한 장 수, 덱 장 수). 카드마다 덱에 넣은 수와 보유 수 중 작은 쪽을 센다.
    func deckProgress(_ deck: Deck) -> (owned: Int, total: Int) {
        let cards = deck.cards.filter { db.cidSet.contains($0.key) }  // 시대 범위 밖 카드는 그리드처럼 세지 않는다
        return (cards.reduce(0) { $0 + min(copies($1.key), $1.value) }, cards.values.reduce(0, +))
    }

    /// 새 덱 "새 덱 N".
    @discardableResult
    mutating func addDeck() -> Deck {
        let deck = Deck(name: "새 덱 \(state.decks.count + 1)")
        state.decks.append(deck)
        return deck
    }

    /// 앞뒤 공백을 지운 이름으로 바꾼다. 비면 그대로 둔다.
    mutating func renameDeck(_ id: UUID, to name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let i = state.decks.firstIndex(where: { $0.id == id }) else { return }
        state.decks[i].name = name
    }

    mutating func deleteDeck(_ id: UUID) { state.decks.removeAll { $0.id == id } }

    /// 덱에 1장 넣는다. 미보유 카드도 되고(목표 덱), 카드마다 `maxCopiesInDeck` 장까지. 넣었으면 true.
    mutating func addToDeck(_ id: UUID, _ cid: Int) -> Bool {
        guard let i = state.decks.firstIndex(where: { $0.id == id }) else { return false }
        let n = state.decks[i].cards[cid] ?? 0
        guard n < Balance.maxCopiesInDeck else { return false }
        state.decks[i].cards[cid] = n + 1
        return true
    }

    /// 덱에서 1장 뺀다. 0장이 되면 항목을 지운다.
    mutating func removeFromDeck(_ id: UUID, _ cid: Int) {
        guard let i = state.decks.firstIndex(where: { $0.id == id }), let n = state.decks[i].cards[cid] else { return }
        state.decks[i].cards[cid] = n > 1 ? n - 1 : nil
    }

    // MARK: 융합

    /// 융합에 쓸 소재 (cid → 장 수). 소재가 전부 100팩 카드인 융합 몬스터만, 아니면 nil.
    func fusionMaterials(_ cid: Int) -> [Int: Int]? { db.cards[cid]?.fusionMaterials }

    /// 중복으로 치지 않고 남길 장 수: 1장. 융합 전용 설정이 켜져 있으면 소재로 필요한 최대 장 수 (중복 판매·자동 판매 공통)
    func keep(_ cid: Int) -> Int { state.fusionOnly ? max(1, db.materialNeed[cid] ?? 1) : 1 }

    /// 설정이 켜져 있으면 소재를 아는 융합 몬스터는 팩·무료 카드에서 안 나오고 융합으로만 얻는다.
    func isFusionOnly(_ cid: Int) -> Bool { state.fusionOnly && fusionMaterials(cid) != nil }

    /// 「융합」 마법 카드가 있어야 융합이 열린다 (소비하지 않는다)
    var hasFusionSpell: Bool { copies(CardDB.fusionSpell) > 0 }

    func canFuse(_ cid: Int) -> Bool {
        hasFusionSpell && fusionMaterials(cid)?.allSatisfy { copies($0.key) >= $0.value } == true
    }

    /// 소재를 소비해(1장은 남긴다) 1장 만든다 (중복 자동 판매는 적용하지 않는다). 「융합」이 없거나 소재가 모자라면 false.
    @discardableResult
    mutating func fuse(_ cid: Int) -> Bool {
        guard let materials = fusionMaterials(cid), canFuse(cid) else { return false }
        for (m, n) in materials { state.owned[m] = max(1, copies(m) - n) }  // 마지막 1장은 남겨 컬렉션에서 빠지지 않는다
        give(cid, source: "융합")
        return true
    }

    // MARK: 뽑기

    /// 전체 카드에서 `freeWeights`로 티어를 고르고 그 안에서 균등 선택.
    /// 그 티어가 비었으면 팩과 같이 아래 → 위 티어 순으로 찾는다.
    func drawFree<R: RandomNumberGenerator>(using rng: inout R) -> Int? {
        var byTier: [Int: [Int]] = [:]
        for cid in db.allCIDs where !isFusionOnly(cid) {
            byTier[db.tier(cid), default: []].append(cid)
        }
        for t in Self.fallbackOrder(pickTier(Balance.freeWeights, using: &rng)) {
            if let cid = byTier[t]?.randomElement(using: &rng) { return cid }
        }
        return nil
    }

    static func fallbackOrder(_ tier: Int) -> [Int] {
        [tier] + Array(stride(from: tier - 1, through: 1, by: -1)) + Array(stride(from: tier + 1, through: CardInfo.rarities.count, by: 1))
    }

    /// 팩에서 tier → 아래 티어들 → 위 티어들 순으로, excluding(같은 팩에서 이미 나온 카드)에 없는 카드를 균등 선택.
    /// kind(몬스터·마법·함정)가 있으면 그 종류만. 보유 수 상한은 없다.
    func draw<R: RandomNumberGenerator>(pack: Int, tier: Int, excluding: Set<Int> = [], kind: String? = nil, using rng: inout R) -> Int? {
        for t in Self.fallbackOrder(tier) {
            let candidates = db.packs[pack].cards.filter {
                db.tier($0) == t && !excluding.contains($0) && !isFusionOnly($0) && (kind == nil || db.cards[$0]?.kind == kind)
            }
            if let cid = candidates.randomElement(using: &rng) { return cid }
        }
        return nil
    }

    func slot5Tier<R: RandomNumberGenerator>(using rng: inout R) -> Int {
        pickTier(Balance.slot5Weights, using: &rng)
    }

    func pickTier<R: RandomNumberGenerator>(_ weights: [(tier: Int, weight: Double)], using rng: inout R) -> Int {
        var r = Double.random(in: 0..<1, using: &rng)
        for (tier, weight) in weights {
            if r < weight { return tier }
            r -= weight
        }
        return weights[weights.count - 1].tier
    }

    /// 1팩 구매. 코인으로 산 팩 `packsPerFreePack`개마다 무료 팩 1장이 쌓인다. 코인이 부족하면 빈 배열.
    mutating func buy<R: RandomNumberGenerator>(pack: Int, using rng: inout R) -> [Pull] {
        // 시대 범위를 줄인 뒤 남아 있는 옛 인덱스(개봉 화면의 [한 팩 더] 등)는 거절
        guard db.packs.indices.contains(pack), canBuy(pack) else { return [] }
        state.coins -= Balance.packPrice
        state.packStamp += 1
        if state.packStamp >= Balance.packsPerFreePack {
            state.packStamp = 0
            state.freePacks += 1
        }
        return open(pack: pack, using: &rng)
    }

    /// 쌓인 무료 팩 1개를 연다. 정규 부스터 팩 중 하나를 무작위로 고른다. 없으면 nil.
    mutating func openFreePack<R: RandomNumberGenerator>(using rng: inout R) -> (pack: Int, pulls: [Pull])? {
        guard state.freePacks > 0, !db.packs.isEmpty else { return nil }
        state.freePacks -= 1
        let pack = Int.random(in: db.packs.indices, using: &rng)
        return (pack, open(pack: pack, using: &rng))
    }

    /// 봉투 하나 열기: 노멀 4 + 슬롯5. 앞 `monstersPerPack` 장은 몬스터만 뽑아 마법·함정만 나오는 봉투가 없게 한다.
    private mutating func open<R: RandomNumberGenerator>(pack: Int, using rng: inout R) -> [Pull] {
        let tiers = [1, 1, 1, 1, slot5Tier(using: &rng)]
        var pulls: [Pull] = []
        for (i, tier) in tiers.enumerated() {
            let kind = i < Balance.monstersPerPack ? "몬스터" : nil
            guard let cid = draw(pack: pack, tier: tier, excluding: Set(pulls.map(\.cid)), kind: kind, using: &rng) else { continue }
            let isNew = copies(cid) == 0
            give(cid, source: db.packs[pack].pid)
            pulls.append(Pull(cid: cid, tier: db.tier(cid), isNew: isNew, soldFor: autoSell(cid)))
        }
        return pulls
    }

    /// 설정이 켜져 있고 `keep` 장을 넘으면 바로 1장 판다. 반환: 받은 코인.
    private mutating func autoSell(_ cid: Int) -> Int? {
        guard state.autoSellDuplicates, copies(cid) > keep(cid) else { return nil }
        return sell(cid)
    }

    mutating func give(_ cid: Int, source: String, now: Date = Date()) {
        state.owned[cid, default: 0] += 1
        state.log.insert(LogEntry(cid: cid, source: source, date: now), at: 0)
        if state.log.count > Balance.logLimit {
            state.log.removeLast(state.log.count - Balance.logLimit)
        }
    }

    /// 마지막으로 산 팩 (팝오버 바로 구매용). 산 적이 없으면 첫 팩.
    var lastBoughtPack: Int {
        for entry in state.log {
            if let i = db.packs.firstIndex(where: { $0.pid == entry.source }) { return i }
        }
        return 0
    }
}
