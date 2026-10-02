import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var game: Game
    /// 마지막 구매 결과 (팩 개봉 창이 보여줌)
    @Published private(set) var opening: [Pull] = []
    @Published private(set) var openingID = UUID()
    @Published var showShop = false
    @Published var showSettings = false
    /// 오늘 provider별 토큰·비용 (팝오버 사용량 표시)
    @Published private(set) var todayTokens: [String: Int] = [:]
    @Published private(set) var todayCost: [String: Double] = [:]
    /// 공식 한도 (Claude: OAuth usage, Codex: app-server). 못 읽으면 nil.
    @Published private(set) var claudeLimits: LimitStatus?
    @Published private(set) var codexLimits: CodexRateLimitSnapshot?

    private let store: StateStore
    private var rng = SystemRandomNumberGenerator()
    private var timer: Timer?
    private var refreshing = false
    private var limitsTimer: Timer?
    private var fetchingLimits = false
    /// 키체인 암호 창을 이번 실행에서 이미 띄웠으면(거절 포함) 자동 갱신은 다시 띄우지 않는다.
    private var keychainPrompted = false

    init(db: CardDB, store: StateStore = .standard()) {
        self.store = store
        self.game = Game(db: db, state: store.load())
    }

    var db: CardDB { game.db }

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refreshLimits()
        // ponytail: 5분 고정 주기. 429 가 잦으면 Retry-After 백오프 추가
        limitsTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshLimits() }
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
            let usage = await Task.detached { TodayUsage.read() }.value
            todayTokens = usage.byProvider
            todayCost = usage.cost
            game.claim(today: usage.date, byProvider: usage.byProvider)
            save()
        }
    }

    @discardableResult
    func buy(pack: Int) -> Bool {
        let opened = game.buy(pack: pack, using: &rng)
        guard !opened.isEmpty else { return false }
        opening = opened
        openingID = UUID()
        save()
        return true
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
        opening = opened
        openingID = UUID()
        save()
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
        let next = envelope.state.withLedger(of: game.state)
        try store.save(next)
        game.state = next
        return backup
    }

    private func save() {
        do { try store.save(game.state) } catch { AppLog.write("state 저장 실패: \(error)") }
    }
}
