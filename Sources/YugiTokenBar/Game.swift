import Foundation

enum Balance {
    static let tokensPerCoin = 10_000
    static let packPrice = 1_000
    static let tokensPerFreeCard = 10_000_000
    static let maxCopies = 2
    static let unlockRatio = 0.5
    /// 팩 5번째 장의 티어 확률 (R / SR / UR / 최상위)
    static let slot5Weights: [(tier: Int, weight: Double)] = [(2, 0.70), (3, 0.18), (4, 0.09), (5, 0.03)]
    static let logLimit = 50
}

struct Pull: Sendable, Equatable {
    let cid: Int
    let tier: Int
    let label: String
    let isNew: Bool
}

struct Game: Sendable {
    let db: CardDB
    var state: GameState

    // MARK: 토큰 적립

    /// 오늘의 provider별 누적 토큰을 받아 늘어난 만큼만 적립한다. 원장은 같은 날 안에서 절대 내려가지 않는다
    /// (일시적으로 0이나 작은 값이 읽혀도 나중에 같은 토큰을 두 번 적립하지 않도록). 반환: 이번에 받은 무료 카드 cid.
    mutating func claim<R: RandomNumberGenerator>(today: String, byProvider: [String: Int], using rng: inout R) -> [Int] {
        guard state.claimedDate != nil else {
            // 첫 실행: 설치 전 사용량은 적립하지 않는다.
            state.claimedDate = today
            state.claimedByProvider = byProvider
            return []
        }
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
        return credit(delta, using: &rng)
    }

    mutating func credit<R: RandomNumberGenerator>(_ tokens: Int, using rng: inout R) -> [Int] {
        guard tokens > 0 else { return [] }
        state.coinRemainder += tokens
        state.coins += state.coinRemainder / Balance.tokensPerCoin
        state.coinRemainder %= Balance.tokensPerCoin
        state.dropProgress += tokens
        var got: [Int] = []
        while state.dropProgress >= Balance.tokensPerFreeCard {
            state.dropProgress -= Balance.tokensPerFreeCard
            guard let cid = drawFree(using: &rng) else { continue }  // 전부 2장이면 게이지만 소모
            give(cid, source: "free")
            state.unseenFree += 1
            got.append(cid)
        }
        return got
    }

    // MARK: 조회

    func copies(_ cid: Int) -> Int { state.owned[cid] ?? 0 }

    var ownedDistinct: Int { state.owned.values.filter { $0 > 0 }.count }

    func progress(_ pack: Int) -> (owned: Int, total: Int) {
        let cards = db.packs[pack].cards
        return (cards.filter { copies($0.cid) > 0 }.count, cards.count)
    }

    func isUnlocked(_ pack: Int) -> Bool { pack < state.unlocked }

    func isComplete(_ pack: Int) -> Bool {
        db.packs[pack].cards.allSatisfy { copies($0.cid) >= Balance.maxCopies }
    }

    func canBuy(_ pack: Int, count: Int = 1) -> Bool {
        isUnlocked(pack) && !isComplete(pack) && state.coins >= Balance.packPrice * count
    }

    // MARK: 뽑기

    /// 전체 카드 중 2장 미만인 카드를 균등 선택(잠긴 팩 카드 포함).
    func drawFree<R: RandomNumberGenerator>(using rng: inout R) -> Int? {
        db.allCIDs.filter { copies($0) < Balance.maxCopies }.randomElement(using: &rng)
    }

    /// 팩에서 tier → 아래 티어들 → 위 티어들 순으로, 2장 미만인 카드를 균등 선택.
    func draw<R: RandomNumberGenerator>(pack: Int, tier: Int, using rng: inout R) -> PackCard? {
        let order = [tier]
            + Array(stride(from: tier - 1, through: 1, by: -1))
            + Array(stride(from: tier + 1, through: 5, by: 1))
        for t in order {
            let candidates = db.packs[pack].cards.filter { $0.tier == t && copies($0.cid) < Balance.maxCopies }
            if let card = candidates.randomElement(using: &rng) { return card }
        }
        return nil
    }

    func slot5Tier<R: RandomNumberGenerator>(using rng: inout R) -> Int {
        var r = Double.random(in: 0..<1, using: &rng)
        for (tier, weight) in Balance.slot5Weights {
            if r < weight { return tier }
            r -= weight
        }
        return Balance.slot5Weights[Balance.slot5Weights.count - 1].tier
    }

    /// count 팩 구매. 도중에 팩이 완료되면 남은 팩은 사지 않는다(코인도 깎지 않음).
    mutating func buy<R: RandomNumberGenerator>(pack: Int, count: Int, using rng: inout R) -> [[Pull]] {
        guard count > 0, canBuy(pack, count: count) else { return [] }
        var opened: [[Pull]] = []
        for _ in 0..<count where !isComplete(pack) {
            state.coins -= Balance.packPrice
            let tiers = [1, 1, 1, 1, slot5Tier(using: &rng)]
            var pulls: [Pull] = []
            for tier in tiers {
                guard let card = draw(pack: pack, tier: tier, using: &rng) else { continue }
                let isNew = copies(card.cid) == 0
                give(card.cid, source: db.packs[pack].pid)
                pulls.append(Pull(cid: card.cid, tier: card.tier, label: card.label, isNew: isNew))
            }
            opened.append(pulls)
        }
        return opened
    }

    mutating func give(_ cid: Int, source: String, now: Date = Date()) {
        state.owned[cid, default: 0] += 1
        state.log.insert(LogEntry(cid: cid, source: source, date: now), at: 0)
        if state.log.count > Balance.logLimit {
            state.log.removeLast(state.log.count - Balance.logLimit)
        }
        // 팩 k 가 50% 이상이면 팩 k+1 해금 (연쇄)
        while state.unlocked < db.packs.count {
            let p = progress(state.unlocked - 1)
            guard Double(p.owned) >= Double(p.total) * Balance.unlockRatio else { break }
            state.unlocked += 1
        }
    }
}
