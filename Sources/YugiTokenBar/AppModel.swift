import SwiftUI

@MainActor @Observable
final class AppModel {
    private(set) var game: Game
    /// 마지막 구매·무료 카드 결과 (팝오버 안 개봉 화면이 보여줌)
    private(set) var opening: [Pull] = []
    private(set) var openingTitle = ""
    /// 지금 개봉 화면의 팩 (무료 카드면 nil). 개봉 화면의 [한 팩 더] 가 쓴다.
    private(set) var openingPack: Int?
    private(set) var openingID = UUID()
    /// 팝오버 안 지금 화면
    var screen: PanelScreen = .summary
    /// 오늘 provider별 토큰·비용 (팝오버 사용량 표시)
    private(set) var todayTokens: [String: Int] = [:]
    private(set) var todayCost: [String: Double] = [:]
    /// 공식 한도 (Claude: OAuth usage, Codex: app-server). 못 읽으면 nil.
    private(set) var claudeLimits: LimitStatus?
    private(set) var codexLimits: CodexRateLimitSnapshot?
    /// 공식 한도를 읽는 중 (사용량 칸이 표시한다)
    private(set) var fetchingLimits = false
    /// 마지막 저장이 실패했으면 그 이유 (팝오버·메뉴바가 경고한다. 다음 저장이 되면 지운다)
    private(set) var saveError: String?

    // 아래는 화면이 읽지 않는 내부 상태라 관찰하지 않는다
    @ObservationIgnored private let store: StateStore
    @ObservationIgnored private var rng = SystemRandomNumberGenerator()
    @ObservationIgnored private var refreshing = false
    /// 키체인 암호 창을 이번 실행에서 이미 띄웠으면(거절 포함) 자동 갱신은 다시 띄우지 않는다.
    @ObservationIgnored private var keychainPrompted = false
    /// 파트너 「날개 크리보」. 해금 전에는 멈춰 있다.
    @ObservationIgnored let partner: PartnerModel
    /// 바탕화면 파트너 창 (해금되고 처음 보일 때 만든다)
    @ObservationIgnored private var partnerPanel: PartnerPanel?
    /// 오늘 사용량 (Claude 로그는 파일별로 캐시)
    @ObservationIgnored private let usageReader = TodayUsageReader()
    @ObservationIgnored private var lastUsage: UsageSample?
    @ObservationIgnored private var tokensPerMinute = 0
    /// 마지막으로 파트너 반응을 계산한 상태
    @ObservationIgnored private var partnerSeen: GameState

    /// partner: 테스트는 `PartnerModel(sheet: nil)` 을 넘겨 실제 창·타이머를 띄우지 않는다.
    init(db: CardDB, store: StateStore = .standard(), partner: PartnerModel? = nil) {
        self.store = store
        self.partner = partner ?? PartnerModel()
        let state = store.load()
        self.game = Game(db: db, state: state)
        self.partnerSeen = state
    }

    var db: CardDB { game.db }

    /// 앱 시작 시 해금 검사 (저장 전 검사와 함께 스펙 §2).
    func unlockOnLaunch() {
        if game.unlockPartnerIfOwned() { save() }
    }

    func start() {
        unlockOnLaunch()
        updatePartner()
        every(.seconds(60)) { $0.refresh() }
        // ponytail: 5분 고정 주기. 429 가 잦으면 Retry-After 백오프 추가
        every(.seconds(300)) { $0.refreshLimits() }
    }

    /// 바로 한 번, 그 뒤 period 마다. 앱 수명 동안 돈다(모델이 사라지면 멈춘다).
    private func every(_ period: Duration, _ action: @escaping (AppModel) -> Void) {
        Task { [weak self] in
            while true {
                // 쉬는 동안 모델을 붙잡지 않도록 부를 때만 꺼낸다
                if let self { action(self) } else { return }
                try? await Task.sleep(for: period)
            }
        }
    }

    /// userInitiated = 사용자가 사용량 칸을 눌렀을 때. 그때만 키체인 창을 다시 띄울 수 있다.
    func refreshLimits(userInitiated: Bool = false) {
        guard !fetchingLimits else { return }
        fetchingLimits = true
        Task {
            defer { fetchingLimits = false }
            async let codex = try? CodexRateLimitsProvider().fetch()
            claudeLimits = await fetchClaude(allowPrompt: userInitiated) ?? claudeLimits
            if let codex = await codex { codexLimits = codex.visibleSnapshots.first }
            updatePartnerMood()
        }
    }

    /// 자동 갱신은 키체인을 읽지 않는 경로(~/.claude/.credentials.json·메모리 캐시)를 먼저 쓰고,
    /// 그게 안 되면 실행당 한 번만 키체인을 연다('항상 허용'이면 창 없이 통과).
    private func fetchClaude(allowPrompt: Bool) async -> LimitStatus? {
        let provider = OAuthLimitsProvider()
        do {
            return try await provider.fetch(allowKeychainPrompt: allowPrompt)
        } catch LimitsError.keychainInteractionNotAllowed where !keychainPrompted {
            keychainPrompted = true
            do { return try await provider.fetch(allowKeychainPrompt: true) } catch {
                AppLog.write("claude limits: \(error)")
                return nil
            }
        } catch {
            AppLog.write("claude limits: \(error)")
            return nil
        }
    }

    func refresh() {
        guard !refreshing else { return }
        refreshing = true
        Task {
            defer { refreshing = false }
            let usage = await usageReader.read(since: game.state.claimedDate)  // actor 라서 메인 스레드 밖에서 읽는다
            // 같은 값이라도 넣으면 읽는 화면이 다시 그려질 수 있어 바뀔 때만
            if todayTokens != usage.byProvider { todayTokens = usage.byProvider }
            if todayCost != usage.cost { todayCost = usage.cost }
            let sample = UsageSample(date: usage.date, total: usage.byProvider.values.reduce(0, +), at: Date())
            tokensPerMinute = PartnerMood.tokensPerMinute(from: lastUsage, to: sample)
            lastUsage = sample
            updatePartnerMood()
            claim(today: usage.date, byProvider: usage.byProvider, earlier: usage.earlier)
        }
    }

    /// 늘어난 토큰이 있을 때만 적립하고 저장한다. 쉬는 중이면 상태가 그대로라 저장도, 화면 다시 그리기도 하지 않는다.
    func claim(today: String, byProvider: [String: Int], earlier: [String: [String: Int]] = [:]) {
        var next = game
        next.claim(today: today, byProvider: byProvider, earlier: earlier)
        guard next.state != game.state else { return }
        game = next
        save()
    }

    @discardableResult
    func buy(pack: Int) -> Bool {
        let opened = game.buy(pack: pack, using: &rng)
        guard !opened.isEmpty else { return false }
        show(opened, title: db.packs[pack].name, pack: pack)
        return true
    }

    @discardableResult
    func openFreePack() -> Bool {
        guard let (pack, pulls) = game.openFreePack(using: &rng) else { return false }
        show(pulls, title: "무료 팩 · \(db.packs[pack].name)", pack: pack)
        return true
    }

    /// 팝오버 안 개봉 화면으로 보여준다.
    private func show(_ pulls: [Pull], title: String, pack: Int? = nil) {
        opening = pulls
        openingTitle = title
        openingPack = pack
        openingID = UUID()
        // 개봉 중에 또 열면(한 팩 더) 돌아갈 곳은 그대로
        if case .opening = screen {} else { screen = .opening(back: screen) }
        if pulls.contains(where: { $0.tier >= 3 }) { partner.play(.excited) }
        save()
    }

    /// 개봉 화면을 닫고 연 화면(요약·상점)으로 돌아간다.
    func closeOpening() {
        if case .opening(let back) = screen { screen = back }
    }

    var autoSellDuplicates: Bool {
        get { game.state.autoSellDuplicates }
        set { game.state.autoSellDuplicates = newValue; save() }
    }

    var eraLimit: String {
        get { game.state.eraLimit }
        set { game.state.eraLimit = newValue; save() }
    }

    var fusionOnly: Bool {
        get { game.state.fusionOnly }
        set { game.state.fusionOnly = newValue; save() }
    }

    var animationsOff: Bool {
        get { game.state.animationsOff }
        set { game.state.animationsOff = newValue; save() }
    }

    var partnerEnabled: Bool {
        get { game.state.partnerEnabled }
        set { guard newValue != game.state.partnerEnabled else { return }; game.state.partnerEnabled = newValue; save(); updatePartner() }
    }

    var partnerSize: Double {
        get { game.state.partnerSize }
        set { guard newValue != game.state.partnerSize else { return }; game.state.partnerSize = newValue; save(); updatePartner() }
    }

    /// 개봉 화면에서 자동 판매된 i 번째 카드를 판매 취소
    func keepSold(at i: Int) {
        guard opening.indices.contains(i), let coins = opening[i].soldFor,
              game.unsell(opening[i].cid, refund: coins) else { return }
        opening[i].soldFor = nil
        save()
    }

    func fuse(_ cid: Int) {
        guard game.fuse(cid) else { return }
        save()
    }

    // MARK: 덱

    @discardableResult
    func addDeck() -> Deck { let deck = game.addDeck(); save(); return deck }
    func renameDeck(_ id: UUID, to name: String) { game.renameDeck(id, to: name); save() }
    func deleteDeck(_ id: UUID) { game.deleteDeck(id); save() }

    /// 카드마다 1장씩 빼고 한 번만 저장한다 (여러 장 선택).
    func removeFromDeck(_ id: UUID, _ cids: some Sequence<Int>) {
        for cid in cids { game.removeFromDeck(id, cid) }
        save()
    }

    /// 카드마다 1장씩 넣고 넣은 게 있으면 한 번만 저장한다. 반환: 넣은 장 수 (3장 한도에 걸린 카드는 빠진다).
    @discardableResult
    func addToDeck(_ id: UUID, _ cids: some Sequence<Int>) -> Int {
        var added = 0
        for cid in cids where game.addToDeck(id, cid) { added += 1 }
        if added > 0 { save() }
        return added
    }

    func toggleFavorite(_ cid: Int) {
        if game.state.favorites.remove(cid) == nil { game.state.favorites.insert(cid) }
        save()
    }

    func sell(_ cid: Int) {
        guard game.sell(cid) != nil else { return }
        save()
    }

    func sellDuplicates() {
        guard game.sellDuplicates() > 0 else { return }
        save()
    }

    @discardableResult
    func openFree() -> Bool {
        let opened = game.openFree(using: &rng)
        guard !opened.isEmpty else { return false }
        show(opened, title: "무료 카드")
        return true
    }

    /// 세이브 폴더 (YTB_STATE_DIR 를 따른다)
    var saveFolder: URL { store.url.deletingLastPathComponent() }

    func exportedSave() throws -> Data {
        try SaveEnvelope(appVersion: AppInfo.currentVersion, exportedAt: Date(), state: game.state).encoded()
    }

    /// 현재 세이브를 백업한 뒤 바꾼다. 백업 파일 URL 을 돌려준다.
    func importSave(_ envelope: SaveEnvelope) throws -> URL {
        let backup = try store.backupBeforeImport(game.state, appVersion: AppInfo.currentVersion)
        var imported = Game(db: db, state: envelope.state.withLedger(of: game.state))
        imported.unlockPartnerIfOwned()  // 가져온 세이브에 날개 크리보가 있으면 해금 (한 번만 써서 .bak 은 가져오기 전 세이브로 남는다)
        try store.save(imported.state)
        game.state = imported.state
        partnerSeen = imported.state
        updatePartner()
        return backup
    }

    private func save() {
        let unlocked = game.unlockPartnerIfOwned()
        do {
            try store.save(game.state)
            if saveError != nil { saveError = nil }
        } catch {
            AppLog.write("state 저장 실패: \(error)")
            saveError = error.localizedDescription
        }
        if unlocked { updatePartner() }  // 타이머를 먼저 켜야 아래 반응이 재생된다
        for anim in PartnerAnim.reactions(from: partnerSeen, to: game.state, newlyUnlocked: unlocked) { partner.play(anim) }
        partnerSeen = game.state
    }

    // MARK: 파트너

    private func updatePartnerMood() {
        let meters = (claudeLimits.map(UsageView.claudeMeters) ?? []) + (codexLimits.map(UsageView.codexMeters) ?? [])
        partner.setMood(.base(tokensPerMinute: tokensPerMinute, limitPercent: PartnerMood.limitPercent(meters)))
    }

    /// 해금·설정에 맞춰 파트너를 돌리고 바탕화면 창을 보이거나 숨긴다.
    func updatePartner() {
        guard game.state.partnerUnlocked, partner.isReady else { partnerPanel?.hide(); return }
        partner.start()
        guard game.state.partnerEnabled else { partnerPanel?.hide(); return }
        let panel = partnerPanel ?? PartnerPanel(
            frame: partner.desktop,
            onClick: { [weak self] in self?.partner.interrupt(.puzzled) },
            onHide: { [weak self] in self?.partnerEnabled = false },
            onMoved: { [weak self] origin in
                self?.game.state.partnerOrigin = origin
                self?.save()
            })
        partnerPanel = panel
        panel.show(size: game.state.partnerSize, origin: game.state.partnerOrigin)
    }
}

/// 팝오버 안 화면. 개봉은 연 화면(요약·상점) 위에 뜨고, 닫으면 그리로 돌아간다.
enum PanelScreen: Equatable {
    case summary, shop, settings
    indirect case opening(back: PanelScreen)
}
