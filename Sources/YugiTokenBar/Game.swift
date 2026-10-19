import Foundation

enum Balance {
    static let tokensPerCoin = 10_000
    static let packPrice = 1_000
    /// 코인으로 이만큼 사면 무료 팩 1장 (무료 팩으로 깐 건 세지 않는다)
    static let packsPerFreePack = 10
    /// 이스터에그: 「욕망의 항아리」(드로우 2장)가 나오면 무료 팩을 이만큼 준다 (팩·무료 카드 모두, 자동 판매돼도)
    static let potOfGreedFreePacks = 2
    static let tokensPerFreeCard = 10_000_000
    /// 첫 실행에 적립하는 지난 일수. 그 전 사용량은 적립하지 않는다 (catchUpDays 30 안)
    static let firstRunCreditDays = 14
    /// 팩 4번째 장이 노멀 대신 레어(R)가 될 확률
    static let slot4RareChance = 0.30
    /// 팩 5번째 장의 티어 확률 (R / SR / UR / SE). 그 티어가 없는 팩은 아래 → 위 티어 순으로 찾는다.
    static let slot5Weights: [(tier: Int, weight: Double)] = [(2, 0.70), (3, 0.18), (4, 0.10), (5, 0.02)]
    /// 무료 카드의 티어 확률 (N / R / SR / UR / SE). 티어 안에서는 균등.
    static let freeWeights: [(tier: Int, weight: Double)] = [(1, 0.70), (2, 0.23), (3, 0.05), (4, 0.015), (5, 0.005)]
    static let logLimit = 50
    /// 무료 카드를 한 번에 여는 최대 장 수 (팩 1봉투와 같은 5장)
    static let freeOpenBatch = 6
    /// 팩 1봉투에서 몬스터를 보장하는 장 수. 노멀 슬롯 앞에서부터 이만큼은 몬스터만 뽑는다 (모든 팩에 노멀 몬스터 13장 이상).
    static let monstersPerPack = 2
    /// 카드 1장 판매가 (티어 → 코인). 팩 기대 판매가 ≈ 215 < packPrice 라 사고팔기로 코인이 늘지 않는다.
    static let sellPrice: [Int: Int] = [1: 20, 2: 50, 3: 150, 4: 400, 5: 1_200]
    /// 종류를 다 모은 팩(`PackProgress.cleared`)에 든 카드의 판매가 배수. 그래도 팩 기대 판매가 ≈ 645 < packPrice
    static let clearedSellMultiplier = 3
    /// 다 모은 팩에서 아직 필요한 카드(`Game.wanted`)가 같은 등급의 다른 카드보다 이만큼 잘 나온다
    static let wantedWeight = 10.0
    /// 덱에 같은 카드를 넣을 수 있는 최대 장 수 (유희왕 규칙)
    static let maxCopiesInDeck = 3
    /// 같은 카드를 이만큼 모으면 공식 오버프레임 그림이 해금된다 (판이 있는 카드만, 팔아도 유지). 해금 전엔 이만큼 자동 판매·중복 판매에서 남긴다.
    static let overframeCopies = 3
    /// 메인 덱 권장 장 수. 표시만 하고 강제하지 않는다.
    static let deckSize = 40...60
}

struct PackProgress {
    var owned = 0
    let total: Int
    /// 남은 미보유 융합 전용 카드 수 (설정 [융합 몬스터는 융합으로만]일 때만. 융합으로만 채운다)
    var fusionLeft = 0
    /// 다 모은 팩(`cleared`)에서 아직 필요한 카드 수 (`Game.wanted`: 해금 전 오버프레임·모자란 융합 소재)
    var wanted = 0
    /// 모든 카드를 1장 이상 가졌다
    var complete: Bool { owned == total }
    /// 팩에서 더 받을 카드가 없다: 다 모았거나 남은 미보유가 융합 전용뿐. 상점 도장(COMPLETE·FUSION ONLY)·구매 막기
    var cleared: Bool { owned + fusionLeft == total }
    /// 다 모았고 필요한 카드도 없다: 상점 구매를 한 번 막는다
    var done: Bool { cleared && wanted == 0 }
}

struct Pull: Sendable, Equatable {
    let cid: Int
    let tier: Int
    let isNew: Bool
    /// 중복 자동 판매로 바로 판 경우 받은 코인
    var soldFor: Int? = nil
    /// 받은 직후 오버프레임 그림이 해금돼 있었는지 (한 팩에 2·3장째가 같이 나오면 3장째부터)
    var overframe = false
    /// 「욕망의 항아리」로 받은 무료 팩 수
    var bonusPacks = 0
    var label: String { CardInfo.rarities[tier - 1] }
}

struct Game: Sendable {
    /// 101팩 전체
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

    /// 첫 실행에 읽기 시작할 날짜(오늘 − firstRunCreditDays, 지역 날짜). 원장이 없을 때 `read(since:)`에 넘긴다
    static func firstRunSince(now: Date = Date()) -> String {
        let day = Calendar.current.date(byAdding: .day, value: -Balance.firstRunCreditDays, to: now) ?? now
        return LocalUsageReader.localDayFormatter().string(from: day)
    }

    /// 오늘의 provider별 누적 토큰을 받아 늘어난 만큼만 적립한다. 원장은 같은 날 안에서 절대 내려가지 않는다
    /// (일시적으로 0이나 작은 값이 읽혀도 나중에 같은 토큰을 두 번 적립하지 않도록). 반환: 이번에 쌓인 무료 카드 장 수.
    /// earlier: 원장 날짜부터 어제까지의 날짜별 누적. 날짜가 바뀌면 원장 날짜는 남은 만큼, 그 뒤 앱이 꺼져 있던 날은 전부 적립한다.
    @discardableResult
    mutating func claim(today: String, byProvider: [String: Int], earlier: [String: [String: Int]] = [:]) -> Int {
        if state.claimedDate == nil {
            // 첫 실행: 지난 firstRunCreditDays일(earlier)과 오늘을 전부 적립한다. 읽힌 사용량이 없으면 다음 갱신에서 다시 첫 실행으로 본다.
            guard byProvider.values.contains(where: { $0 > 0 }) || earlier.values.contains(where: { $0.values.contains(where: { $0 > 0 }) }) else { return 0 }
            state.claimedDate = earlier.keys.min() ?? today
            state.claimedByProvider = [:]
        }
        if let d = state.claimedDate, today < d { return 0 }  // 시계/시간대가 과거로 가도 원장을 리셋하지 않는다.
        var delta = 0
        if let d = state.claimedDate, d != today {
            for (day, totals) in earlier where d <= day && day < today {
                delta += Self.increase(from: day == d ? state.claimedByProvider : [:], to: totals)
            }
            state.claimedDate = today
            state.claimedByProvider = [:]
        }
        delta += Self.increase(from: state.claimedByProvider, to: byProvider)
        for (provider, current) in byProvider where current > state.claimedByProvider[provider] ?? 0 {
            state.claimedByProvider[provider] = current
        }
        return credit(delta)
    }

    /// provider별로 원장보다 늘어난 만큼의 합 (줄어든 provider 는 0)
    private static func increase(from claimed: [String: Int], to current: [String: Int]) -> Int {
        current.reduce(0) { $0 + max(0, $1.value - (claimed[$1.key] ?? 0)) }
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
            pulls.append(pull(cid, source: LogEntry.free))
        }
        return pulls
    }

    // MARK: 조회

    func copies(_ cid: Int) -> Int { state.owned[cid] ?? 0 }
    func hasOverframe(_ cid: Int) -> Bool { db.cards[cid]?.imageId.map { ImageSource.overframe[$0] != nil } ?? false }
    func showsOverframe(_ cid: Int) -> Bool { state.overframes.contains(cid) }
    /// 오버프레임 판이 있는데 아직 해금하지 않았다: 판매·융합 소재로 쓰지 않고 모은다
    func overframeLocked(_ cid: Int) -> Bool { hasOverframe(cid) && !showsOverframe(cid) }

    /// 시대 범위 안의 즐겨찾기 수 (사이드바 숫자 = 즐겨찾기 목록 장 수)
    var favoritesInRange: Int { state.favorites.filter { db.cidSet.contains($0) }.count }

    /// 시대 범위 안에서 1장 이상 가진 종류 수
    var ownedDistinct: Int { db.allCIDs.filter { copies($0) > 0 }.count }

    /// 시대 범위 안 등급(1~5)별 보유 종류 수 / 전체 종류 수. 인덱스 0 = N
    var tierProgress: [(owned: Int, total: Int)] {
        var out = Array(repeating: (owned: 0, total: 0), count: CardInfo.rarities.count)
        for cid in db.allCIDs {
            let i = db.tier(cid) - 1
            out[i].total += 1
            if copies(cid) > 0 { out[i].owned += 1 }
        }
        return out
    }

    /// 시대 범위 안 오버프레임 판이 있는 카드의 해금 수 / 전체 수
    var overframeProgress: (owned: Int, total: Int) {
        db.allCIDs.filter(hasOverframe).reduce((0, 0)) { sum, cid in (sum.0 + (showsOverframe(cid) ? 1 : 0), sum.1 + 1) }
    }

    /// 팩 진행도를 한 번에 센다 (상점은 모든 팩을 그릴 때마다 부른다)
    func progress(_ pack: Int) -> PackProgress {
        var p = PackProgress(total: db.packs[pack].cards.count)
        for cid in db.packs[pack].cards {
            if copies(cid) > 0 { p.owned += 1 } else if isFusionOnly(cid) { p.fusionLeft += 1 }
        }
        if p.cleared { p.wanted = db.packs[pack].cards.filter(wanted).count }  // 다 모은 팩만 센다 (keep 이 무거워서)
        return p
    }

    /// 시대 묶음 헤더의 보유/전체
    func progress(packs: Range<Int>) -> (owned: Int, total: Int) {
        packs.reduce((0, 0)) { sum, i in
            let p = progress(i)
            return (sum.0 + p.owned, sum.1 + p.total)
        }
    }

    var canAffordPack: Bool { state.coins >= Balance.packPrice }

    // MARK: 판매

    /// 1장 판매가. 카드가 든 팩 중 하나라도 종류를 다 모았으면 `clearedSellMultiplier` 배
    func sellPrice(_ cid: Int) -> Int {
        sellPrice(cid, cleared: db.packs.indices.contains { db.packs[$0].cards.contains(cid) && progress($0).cleared })
    }

    private func sellPrice(_ cid: Int, cleared: Bool) -> Int {
        (Balance.sellPrice[db.tier(cid)] ?? 0) * (cleared ? Balance.clearedSellMultiplier : 1)
    }

    /// 종류를 다 모은 팩에 든 카드 (중복 판매처럼 여러 장을 셀 때 한 번만 센다)
    private var clearedPackCards: Set<Int> {
        Set(db.packs.indices.filter { progress($0).cleared }.flatMap { db.packs[$0].cards })
    }

    /// 1장 판매. 보유하지 않았으면 nil, 팔았으면 받은 코인.
    mutating func sell(_ cid: Int) -> Int? { sell(cid, price: sellPrice(cid)) }

    private mutating func sell(_ cid: Int, price: Int) -> Int? {
        guard copies(cid) > 0 else { return nil }
        state.owned[cid] = copies(cid) == 1 ? nil : copies(cid) - 1
        state.coins += price
        return price
    }

    /// 자동 판매 취소: 받은 코인을 돌려주고 카드를 1장 되돌린다. 그사이 코인을 써서 모자라면 false.
    mutating func unsell(_ cid: Int, refund: Int) -> Bool {
        guard state.coins >= refund else { return false }
        state.coins -= refund
        state.owned[cid, default: 0] += 1
        unlockOverframe(cid)
        return true
    }

    /// 중복분(`keep` 장 넘는 것)을 팔면 받을 (장 수, 코인). 각 카드 `keep` 장은 남는다.
    var duplicatesValue: (count: Int, coins: Int) {
        let cleared = clearedPackCards
        return state.owned.filter { db.cidSet.contains($0.key) }.reduce((0, 0)) { acc, kv in
            let extra = kv.value - keep(kv.key)
            return extra > 0 ? (acc.0 + extra, acc.1 + extra * sellPrice(kv.key, cleared: cleared.contains(kv.key))) : acc
        }
    }

    /// 시대 범위 안 카드의 중복분을 모두 판다(범위 밖은 숨겨져 있으니 건드리지 않는다). 반환: 받은 코인.
    mutating func sellDuplicates() -> Int {
        var total = 0
        let cleared = clearedPackCards  // 중복만 팔아 1장씩은 남으니 도중에 바뀌지 않는다
        for (cid, n) in state.owned where n > keep(cid) && db.cidSet.contains(cid) {
            let price = sellPrice(cid, cleared: cleared.contains(cid))
            for _ in keep(cid)..<n { total += sell(cid, price: price) ?? 0 }
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

    /// 오버프레임 판이 있는 카드를 `overframeCopies` 장 이상 가지면 그 그림을 해금한다. 해금은 팔아도 유지된다.
    mutating func unlockOverframe(_ cid: Int) {
        guard copies(cid) >= Balance.overframeCopies, hasOverframe(cid) else { return }
        state.overframes.insert(cid)
    }

    /// 세이브를 열거나 가져올 때 이미 모아 둔 카드를 해금한다
    mutating func unlockOwnedOverframes() {
        for cid in state.owned.keys { unlockOverframe(cid) }
    }

    // MARK: 덱

    func deck(_ id: UUID) -> Deck? { state.decks.first { $0.id == id } }

    /// 덱의 (보유한 장 수, 덱 장 수). 카드마다 덱에 넣은 수와 보유 수 중 작은 쪽을 센다.
    func deckProgress(_ deck: Deck) -> (owned: Int, total: Int) {
        let cards = deck.cards.filter { db.cidSet.contains($0.key) }  // 시대 범위 밖 카드는 그리드처럼 세지 않는다
        return (cards.reduce(0) { $0 + min(copies($1.key), $1.value) }, cards.values.reduce(0, +))
    }

    /// 새 덱 "새 덱 N" (덱 수 + 1부터, 다른 기본 이름과 겹치지 않는 첫 번호). 화면에는 `Deck.title` 로 지금 언어로 보인다.
    @discardableResult
    mutating func addDeck() -> Deck {
        let used = Set(state.decks.compactMap(\.defaultNumber))
        var n = state.decks.count + 1
        while used.contains(n) { n += 1 }
        let deck = Deck(name: "새 덱 \(n)")
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

    /// 중복으로 치지 않고 남길 장 수: 1장. 융합 전용 설정이 켜져 있으면 소재로 필요한 최대 장 수 (중복 판매·자동 판매 공통).
    /// 조건 소재는 그 융합을 아직 안 가졌을 때만 센다(같은 카드만 나와도 모아서 만들 수 있게).
    /// 오버프레임 판이 있는 카드는 해금 전까지 `overframeCopies` 장 (설정과 상관없이).
    func keep(_ cid: Int) -> Int {
        let base = overframeLocked(cid) ? Balance.overframeCopies : 1
        guard state.fusionOnly else { return base }
        let open = db.conditionNeed[cid]?.filter { copies($0.key) == 0 }.values.max() ?? 1
        return max(base, db.materialNeed[cid] ?? 1, open)
    }

    /// 아직 더 모아야 하는 카드: 가진 장 수가 `keep` 보다 적다 (해금 전 오버프레임 3장, 융합 전용 설정의 소재 장 수).
    /// 다 모은 팩에서 `wantedWeight` 배 잘 나온다
    func wanted(_ cid: Int) -> Bool { copies(cid) < keep(cid) }

    /// 설정이 켜져 있으면 만들 수 있는 융합 몬스터(CardInfo.craftable)·마스크드 히어로는 팩·무료 카드에서 안 나오고 융합으로만 얻는다.
    /// 1장이라도 가지면(융합으로 만들었으면) 다시 팩·무료 카드에서 나온다.
    func isFusionOnly(_ cid: Int) -> Bool { state.fusionOnly && db.fusionCIDs.contains(cid) && copies(cid) == 0 }

    /// 마스크드 히어로는 「마스크 체인지」, 나머지는 「융합」이 있어야 만든다 (소비하지 않는다)
    func craftSpell(_ cid: Int) -> Int { db.cards[cid]?.mask == true ? CardDB.maskChange : CardDB.fusionSpell }

    /// 소재 줄 순서대로 고른 카드 (cid → 장 수, join 은 앞 줄에 합친다). 맞는 카드가 하나뿐인 줄(카드 소재)을 먼저 잡고,
    /// 나머지는 줄 순서대로 가진 카드 중 남는 장 수가 많은 것부터(같으면 cid 가 작은 것) 채운다. 하나라도 못 채우면 nil.
    /// 해금 전 오버프레임 카드(`overframeLocked`)는 모으는 중이라 소재로 쓰지 않는다 (그 카드뿐인 융합은 해금 뒤에 만든다).
    func pickMaterials(_ cid: Int) -> [[Int: Int]]? {
        guard let picks = db.cards[cid]?.picks else { return nil }
        var used: [Int: Int] = [:], got = [[Int: Int]](repeating: [:], count: picks.count)
        let left = { (c: Int) in overframeLocked(c) ? 0 : copies(c) - (used[c] ?? 0) }
        let order = picks.indices.sorted { (picks[$0].any.count == 1 ? 0 : 1, $0) < (picks[$1].any.count == 1 ? 0 : 1, $1) }
        for i in order {
            var need = picks[i].count ?? 1
            let pool = picks[i].any.filter { $0 != cid && left($0) > 0 }
            for c in pool.sorted(by: { (left($0), -$0) > (left($1), -$1) }) where need > 0 {
                let k = min(need, left(c))
                got[i][c] = k
                used[c, default: 0] += k
                need -= k
            }
            guard need == 0 else { return nil }
        }
        return zip(picks, got).reduce(into: []) { out, pg in
            if pg.0.join == true, !out.isEmpty { out[out.count - 1].merge(pg.1, uniquingKeysWith: +) } else { out.append(pg.1) }
        }
    }

    /// 만들 때 쓸 소재 (cid → 장 수)
    func craftMaterials(_ cid: Int) -> [Int: Int]? {
        pickMaterials(cid)?.reduce(into: [:]) { $0.merge($1, uniquingKeysWith: +) }
    }

    /// 고른 소재는 가진 장 수 안에서만 잡으니 다 고르면 만들 수 있다
    func canFuse(_ cid: Int) -> Bool { copies(craftSpell(cid)) > 0 && pickMaterials(cid) != nil }

    /// 지금 융합할 수 있는 범위 안 미보유 카드 (설정이 꺼져 있으면 없다)
    var fusable: [Int] {
        guard state.fusionOnly else { return [] }
        return db.allCIDs.filter { db.fusionCIDs.contains($0) && copies($0) == 0 && canFuse($0) }
    }

    /// 소재를 소비해(1장은 남긴다) 1장 만든다 (중복 자동 판매는 적용하지 않는다). 「융합」(마스크드 히어로는 「마스크 체인지」)이 없거나 소재가 모자라면 false.
    @discardableResult
    mutating func fuse(_ cid: Int) -> Bool {
        guard canFuse(cid), let materials = craftMaterials(cid) else { return false }
        for (m, n) in materials { state.owned[m] = max(1, copies(m) - n) }  // 마지막 1장은 남겨 컬렉션에서 빠지지 않는다
        give(cid, source: LogEntry.fusion)
        return true
    }

    /// "융합 가능" 목록을 다 만든다. 만든 융합이 다른 융합의 소재면 그것도 이어서 만들고(즈아크), 더 만들 게 없을 때까지 돈다. 반환: 만든 순서.
    @discardableResult
    mutating func fuseAll() -> [Int] {
        var made: [Int] = []
        while case let batch = fusable, !batch.isEmpty {
            let before = made.count
            for cid in batch where fuse(cid) { made.append(cid) }  // 앞 융합이 소재를 써서 못 만들게 된 건 건너뛴다
            if made.count == before { break }
        }
        return made
    }

    // MARK: 뽑기

    /// 아직 없는 카드 중에서 `freeWeights`로 티어를 고르고 그 안에서 균등 선택(다 가졌으면 전체 카드에서).
    /// 남은 카드가 없는 티어는 빼고 나머지 티어의 비율대로 다시 나눈다(N이 다 차면 R:SR:UR:SE = 23:5:1.5:0.5).
    func drawFree<R: RandomNumberGenerator>(using rng: inout R) -> Int? {
        let pool = db.allCIDs.filter { !isFusionOnly($0) }
        let missing = pool.filter { copies($0) == 0 }
        var byTier: [Int: [Int]] = [:]
        for cid in missing.isEmpty ? pool : missing { byTier[db.tier(cid), default: []].append(cid) }
        let weights = Balance.freeWeights.filter { byTier[$0.tier] != nil }
        guard !weights.isEmpty else { return byTier.values.first?.randomElement(using: &rng) }  // freeWeights 밖 티어뿐
        let total = weights.reduce(0) { $0 + $1.weight }
        return byTier[pickTier(weights.map { ($0.tier, $0.weight / total) }, using: &rng)]?.randomElement(using: &rng)
    }

    static func fallbackOrder(_ tier: Int) -> [Int] {
        [tier] + Array(stride(from: tier - 1, through: 1, by: -1)) + Array(stride(from: tier + 1, through: CardInfo.rarities.count, by: 1))
    }

    /// 팩에서 tier → 아래 티어들 → 위 티어들 순으로, excluding(같은 팩에서 이미 나온 카드)에 없는 카드를 균등 선택.
    /// kind(몬스터·마법·함정)가 있으면 그 종류만. 보유 수 상한은 없다.
    /// boostWanted: 다 모은 팩이면 아직 필요한 카드(`wanted`)를 `wantedWeight` 배 뽑는다.
    func draw<R: RandomNumberGenerator>(pack: Int, tier: Int, excluding: Set<Int> = [], kind: CardKind? = nil,
                                        boostWanted: Bool = false, using rng: inout R) -> Int? {
        for t in Self.fallbackOrder(tier) {
            let candidates = db.packs[pack].cards.filter {
                db.tier($0) == t && !excluding.contains($0) && !isFusionOnly($0) && (kind == nil || db.cards[$0]?.kind == kind)
            }
            guard !candidates.isEmpty else { continue }
            let weights = candidates.map { boostWanted && wanted($0) ? Balance.wantedWeight : 1 }
            var r = Double.random(in: 0..<weights.reduce(0, +), using: &rng)
            for (cid, w) in zip(candidates, weights) {
                if r < w { return cid }
                r -= w
            }
            return candidates.last
        }
        return nil
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
        guard db.packs.indices.contains(pack), canAffordPack else { return [] }
        state.coins -= Balance.packPrice
        state.lastBoughtPid = db.packs[pack].pid
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

    /// 봉투 하나 열기: 노멀 3 + 슬롯4(노멀, `slot4RareChance`로 레어) + 슬롯5. 앞 `monstersPerPack` 장은 몬스터만 뽑아 마법·함정만 나오는 봉투가 없게 한다.
    /// 팩에 아직 없는 카드가 남아 있으면 1장 이상은 새 카드다(`ensureNew`).
    private mutating func open<R: RandomNumberGenerator>(pack: Int, using rng: inout R) -> [Pull] {
        let boost = progress(pack).cleared
        let slot4 = Double.random(in: 0..<1, using: &rng) < Balance.slot4RareChance ? 2 : 1
        let tiers = [1, 1, 1, slot4, pickTier(Balance.slot5Weights, using: &rng)]
        var slots: [(tier: Int, kind: CardKind?, cid: Int)] = []
        for (i, tier) in tiers.enumerated() {
            let kind: CardKind? = i < Balance.monstersPerPack ? .monster : nil
            guard let cid = draw(pack: pack, tier: tier, excluding: Set(slots.map(\.cid)), kind: kind, boostWanted: boost, using: &rng) else { continue }
            slots.append((tier, kind, cid))
        }
        ensureNew(pack: pack, slots: &slots, using: &rng)
        return slots.map { pull($0.cid, source: db.packs[pack].pid) }
    }

    /// 새 카드가 하나도 없으면 한 칸을 팩의 미보유 카드로 바꾼다. 앞 칸부터 그 칸의 등급·종류에 맞는 미보유 카드를 찾고,
    /// 어느 칸에도 안 맞으면(남은 미보유가 다른 등급뿐) 뒤 칸부터 종류가 맞는 칸을 가장 낮은 등급의 미보유 카드로 바꾼다.
    private func ensureNew<R: RandomNumberGenerator>(pack: Int, slots: inout [(tier: Int, kind: CardKind?, cid: Int)], using rng: inout R) {
        guard !slots.isEmpty, !slots.contains(where: { copies($0.cid) == 0 }) else { return }
        let unowned = db.packs[pack].cards.filter { copies($0) == 0 && !isFusionOnly($0) }
        guard let lowest = unowned.map(db.tier).min() else { return }
        for i in slots.indices {
            let fits = unowned.filter { db.tier($0) == slots[i].tier && (slots[i].kind == nil || db.cards[$0]?.kind == slots[i].kind) }
            if let cid = fits.randomElement(using: &rng) { slots[i].cid = cid; return }
        }
        // 몬스터 전용 칸에는 몬스터만 넣는다
        let pool = unowned.filter { db.tier($0) == lowest }
        for i in slots.indices.reversed() {
            let fits = pool.filter { slots[i].kind == nil || db.cards[$0]?.kind == slots[i].kind }
            if let cid = fits.randomElement(using: &rng) { slots[i].cid = cid; return }
        }
    }

    /// 카드 1장 지급: isNew는 지급 전에 계산하고, 지급 뒤 자동 판매까지 처리한다.
    private mutating func pull(_ cid: Int, source: String) -> Pull {
        let isNew = copies(cid) == 0
        let keep = keep(cid)  // 지급 전 값: 오버프레임을 해금한 장(3장째)은 팔지 않는다
        give(cid, source: source)
        let overframe = showsOverframe(cid)
        let bonusPacks = cid == CardDB.potOfGreed ? Balance.potOfGreedFreePacks : 0
        state.freePacks += bonusPacks
        return Pull(cid: cid, tier: db.tier(cid), isNew: isNew, soldFor: autoSell(cid, keep: keep), overframe: overframe, bonusPacks: bonusPacks)
    }

    /// 설정이 켜져 있고 `keep` 장을 넘으면 바로 1장 판다. 반환: 받은 코인.
    private mutating func autoSell(_ cid: Int, keep: Int) -> Int? {
        guard state.autoSellDuplicates, copies(cid) > keep else { return nil }
        return sell(cid)
    }

    mutating func give(_ cid: Int, source: String, now: Date = Date()) {
        state.owned[cid, default: 0] += 1
        unlockOverframe(cid)
        state.log.insert(LogEntry(cid: cid, source: source, date: now), at: 0)
        if state.log.count > Balance.logLimit {
            state.log.removeLast(state.log.count - Balance.logLimit)
        }
        let fmt = LocalUsageReader.localDayFormatter(), day = fmt.string(from: now)
        if state.cardsByDay[day] == nil,
           let cut = Calendar.current.date(byAdding: .day, value: -GameState.cardDaysKept, to: now).map(fmt.string) {
            state.cardsByDay = state.cardsByDay.filter { $0.key > cut }
        }
        state.cardsByDay[day, default: 0] += 1
    }

    /// 마지막으로 코인으로 산 팩 (팝오버 바로 구매용). 산 적이 없거나 시대 범위 밖이면 첫 팩. 필드가 없는 옛 세이브는 로그에서 찾는다.
    var lastBoughtPack: Int {
        if let pid = state.lastBoughtPid { return db.packs.firstIndex { $0.pid == pid } ?? 0 }
        for entry in state.log {
            if let i = db.packs.firstIndex(where: { $0.pid == entry.source }) { return i }
        }
        return 0
    }
}
