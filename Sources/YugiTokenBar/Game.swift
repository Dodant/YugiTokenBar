import Foundation

enum Balance {
    static let tokensPerCoin = 10_000
    static let packPrice = 1_000
    static let tokensPerFreeCard = 10_000_000
    /// 팩 5번째 장의 티어 확률 (R / SR / UR)
    static let slot5Weights: [(tier: Int, weight: Double)] = [(2, 0.70), (3, 0.18), (4, 0.12)]
    /// 무료 카드의 티어 확률 (N / R / SR / UR). 티어 안에서는 균등.
    static let freeWeights: [(tier: Int, weight: Double)] = [(1, 0.60), (2, 0.25), (3, 0.10), (4, 0.05)]
    static let logLimit = 50
    /// 무료 카드를 한 번에 여는 최대 장 수 (팩 1봉투와 같은 5장)
    static let freeOpenBatch = 5
    /// 카드 1장 판매가 (티어 → 코인). 팩 기대 판매가 ≈ 225 < packPrice 라 사고팔기로 코인이 늘지 않는다.
    static let sellPrice: [Int: Int] = [1: 30, 2: 60, 3: 150, 4: 300]
}

struct Pull: Sendable, Equatable {
    let cid: Int
    let tier: Int
    let label: String
    let isNew: Bool
    /// 중복 자동 판매로 바로 판 경우 받은 코인
    var soldFor: Int? = nil
}

struct Game: Sendable {
    let db: CardDB
    var state: GameState

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
            let card = topCard(cid)
            let isNew = copies(cid) == 0
            give(cid, source: "free")
            pulls.append(Pull(cid: cid, tier: card?.tier ?? 1, label: card?.label ?? "", isNew: isNew, soldFor: autoSell(cid)))
        }
        return pulls
    }

    // MARK: 조회

    func copies(_ cid: Int) -> Int { state.owned[cid] ?? 0 }

    var ownedDistinct: Int { state.distinctOwned }

    func progress(_ pack: Int) -> (owned: Int, total: Int) {
        let cards = db.packs[pack].cards
        return (cards.filter { copies($0.cid) > 0 }.count, cards.count)
    }

    /// 팩의 모든 카드를 1장 이상 가졌으면 완료(✓ 표시만, 구매는 계속 가능).
    func isComplete(_ pack: Int) -> Bool {
        db.packs[pack].cards.allSatisfy { copies($0.cid) > 0 }
    }

    func canBuy(_ pack: Int) -> Bool {
        state.coins >= Balance.packPrice
    }

    // MARK: 판매

    /// 재수록 카드는 수록된 팩 중 가장 높은 티어로 친다(판매가·무료 카드 공통).
    func topCard(_ cid: Int) -> PackCard? {
        db.packs.flatMap(\.cards).filter { $0.cid == cid }.max { $0.tier < $1.tier }
    }

    func sellPrice(_ cid: Int) -> Int {
        Balance.sellPrice[topCard(cid)?.tier ?? 1] ?? 0
    }

    /// 1장 판매. 보유하지 않았으면 nil, 팔았으면 받은 코인.
    mutating func sell(_ cid: Int) -> Int? {
        guard copies(cid) > 0 else { return nil }
        state.owned[cid] = copies(cid) == 1 ? nil : copies(cid) - 1
        let price = sellPrice(cid)
        state.coins += price
        return price
    }

    /// 중복분(2장째 이상)을 팔면 받을 (장 수, 코인). 각 카드 1장은 남는다.
    var duplicatesValue: (count: Int, coins: Int) {
        state.owned.reduce((0, 0)) { acc, kv in
            let extra = kv.value - 1
            return extra > 0 ? (acc.0 + extra, acc.1 + extra * sellPrice(kv.key)) : acc
        }
    }

    /// 중복분을 모두 판다. 반환: 받은 코인.
    mutating func sellDuplicates() -> Int {
        var total = 0
        for (cid, n) in state.owned where n > 1 {
            for _ in 1..<n { total += sell(cid) ?? 0 }
        }
        return total
    }

    // MARK: 뽑기

    /// 전체 카드에서 `freeWeights`로 티어를 고르고 그 안에서 균등 선택.
    /// 그 티어가 비었으면 팩과 같이 아래 → 위 티어 순으로 찾는다.
    func drawFree<R: RandomNumberGenerator>(using rng: inout R) -> Int? {
        let tiers = Dictionary(db.packs.flatMap(\.cards).map { ($0.cid, $0.tier) }, uniquingKeysWith: max)
        var byTier: [Int: [Int]] = [:]
        for cid in db.allCIDs {
            byTier[tiers[cid] ?? 1, default: []].append(cid)
        }
        for t in Self.fallbackOrder(pickTier(Balance.freeWeights, using: &rng)) {
            if let cid = byTier[t]?.randomElement(using: &rng) { return cid }
        }
        return nil
    }

    static func fallbackOrder(_ tier: Int) -> [Int] {
        [tier] + Array(stride(from: tier - 1, through: 1, by: -1)) + Array(stride(from: tier + 1, through: 4, by: 1))
    }

    /// 팩에서 tier → 아래 티어들 → 위 티어들 순으로, excluding(같은 팩에서 이미 나온 카드)에 없는 카드를 균등 선택. 보유 수 상한은 없다.
    func draw<R: RandomNumberGenerator>(pack: Int, tier: Int, excluding: Set<Int> = [], using rng: inout R) -> PackCard? {
        for t in Self.fallbackOrder(tier) {
            let candidates = db.packs[pack].cards.filter { $0.tier == t && !excluding.contains($0.cid) }
            if let card = candidates.randomElement(using: &rng) { return card }
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

    /// 1팩 구매. 코인이 부족하면 빈 배열.
    mutating func buy<R: RandomNumberGenerator>(pack: Int, using rng: inout R) -> [Pull] {
        guard canBuy(pack) else { return [] }
        state.coins -= Balance.packPrice
        let tiers = [1, 1, 1, 1, slot5Tier(using: &rng)]
        var pulls: [Pull] = []
        for tier in tiers {
            guard let card = draw(pack: pack, tier: tier, excluding: Set(pulls.map(\.cid)), using: &rng) else { continue }
            let isNew = copies(card.cid) == 0
            give(card.cid, source: db.packs[pack].pid)
            pulls.append(Pull(cid: card.cid, tier: card.tier, label: card.label, isNew: isNew, soldFor: autoSell(card.cid)))
        }
        return pulls
    }

    /// 설정이 켜져 있고 2장째 이상이면 바로 1장 판다. 반환: 받은 코인.
    private mutating func autoSell(_ cid: Int) -> Int? {
        guard state.autoSellDuplicates, copies(cid) > 1 else { return nil }
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
