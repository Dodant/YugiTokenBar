#if os(Linux)
import Foundation

@MainActor final class LinuxModel {
    private(set) var snapshot: LinuxSnapshot
    var game: Game { snapshot.game }
    var readInFlight: Bool { readTask != nil }
    var onPublish: (@MainActor (LinuxSnapshot) -> Void)?
    private var lastPublishedSnapshot: LinuxSnapshot
    private let store: StateStore
    private var service: LinuxUsageService
    private var inbox = LinuxInbox()
    private var readTask: Task<Void, Never>?
    private var historyTask: Task<Void, Never>?
    private var refreshAgain = false
    private var queuedProgress = false
    private var readID: UInt64 = 0
    private var historyID: UInt64 = 0
    private(set) var stateGeneration: UInt64 = 0
    private(set) var lifecycleEpoch: UInt64 = 0
    private(set) var running = false
    private var rng = SystemRandomNumberGenerator()

    init(game: Game, store: StateStore, service: LinuxUsageService = .live()) {
        snapshot = LinuxSnapshot(game: game)
        lastPublishedSnapshot = snapshot
        self.store = store; self.service = service
    }

    func start() {
        guard !running else { return }
        running = true; lifecycleEpoch &+= 1; inbox = LinuxInbox()
        let before = game.state
        snapshot.game.unlockOwnedOverframes()
        snapshot.game.unlockPartnerIfOwned()
        if game.state != before { persist(); publish() }
        refresh(showProgress: true)
    }

    func stop() {
        guard running || readTask != nil || historyTask != nil else { return }
        running = false; lifecycleEpoch &+= 1
        inbox.close(); readTask?.cancel(); historyTask?.cancel()
        refreshAgain = false; queuedProgress = false
        readTask = nil; historyTask = nil
        let changed = snapshot.refreshing || snapshot.loadingHistory
        snapshot.refreshing = false; snapshot.loadingHistory = false
        if changed { publish() }
    }

    func refresh(showProgress: Bool = false, now: Date = Date()) {
        guard running else { return }
        guard readTask == nil else { refreshAgain = true; queuedProgress = queuedProgress || showProgress; return }
        readID &+= 1
        let id = readID, generation = stateGeneration, epoch = lifecycleEpoch
        let service = service, inbox = inbox
        let since = game.state.claimedDate ?? Game.firstRunSince(now: now)
        if showProgress && !snapshot.refreshing { snapshot.refreshing = true; publish() }
        readTask = Task.detached {
            let result: Result<LinuxUsageSnapshot, LinuxInbox.StringFailure>
            do { result = .success(try await service.read(since, now)) }
            catch { result = .failure(.init(message: error.localizedDescription)) }
            inbox.send(.usage(id, generation, epoch, result))
        }
    }

    func loadHistory(now: Date = Date()) {
        guard running, historyTask == nil else { return }
        let date = LocalUsageReader.localDayFormatter().string(from: now)
        guard snapshot.historyDate != date else { return }
        historyID &+= 1
        let id = historyID, generation = stateGeneration, epoch = lifecycleEpoch
        let service = service, inbox = inbox
        snapshot.loadingHistory = true; publish()
        historyTask = Task.detached {
            let result: Result<UsageByDay, LinuxInbox.StringFailure>
            do { result = .success(try await service.history(now)) }
            catch { result = .failure(.init(message: error.localizedDescription)) }
            inbox.send(.history(id, generation, epoch, date, result))
        }
    }

    func drainEvents() {
        for event in inbox.drain() {
            switch event {
            case let .usage(id, generation, epoch, result):
                guard running, id == readID, generation == stateGeneration, epoch == lifecycleEpoch else { continue }
                readTask = nil
                var changed = snapshot.refreshing
                snapshot.refreshing = false
                switch result {
                case let .success(value):
                    changed = changed || snapshot.usageError != nil || snapshot.todayDate != value.date || snapshot.todayDetail != value.detail
                    snapshot.usageError = nil; snapshot.todayDate = value.date; snapshot.todayDetail = value.detail
                    let before = game.state
                    snapshot.game.claim(today: value.date, byProvider: value.byProvider, earlier: value.earlier)
                    if before != game.state || snapshot.dirty { persist(); changed = true }
                case let .failure(error):
                    changed = changed || snapshot.usageError != error.message
                    snapshot.usageError = error.message
                }
                if changed { publish() }
                if refreshAgain {
                    let progress = queuedProgress
                    refreshAgain = false; queuedProgress = false
                    refresh(showProgress: progress)
                }
            case let .history(id, generation, epoch, date, result):
                guard running, id == historyID, generation == stateGeneration, epoch == lifecycleEpoch else { continue }
                historyTask = nil; snapshot.loadingHistory = false
                switch result {
                case let .success(days): snapshot.history = days; snapshot.historyDate = date; snapshot.historyError = nil
                case let .failure(error): snapshot.historyError = error.message
                }
                publish()
            }
        }
    }

    /// Replacing a service invalidates outstanding results and published history.
    func replaceUsageService(_ service: LinuxUsageService, now: Date = Date()) {
        stateGeneration &+= 1
        readTask?.cancel(); historyTask?.cancel(); readTask = nil; historyTask = nil
        refreshAgain = false; queuedProgress = false
        self.service = service; snapshot.history = nil; snapshot.historyDate = nil
        snapshot.loadingHistory = false; snapshot.refreshing = false
        snapshot.historyError = nil; snapshot.usageError = nil
        publish(); refresh(showProgress: true, now: now)
    }

    /// Additional scan roots live in shared reader preferences; rebuild its caches after a change.
    func resetUsageReader(historyFile: URL? = TodayUsageReader.defaultHistoryFile) {
        if let historyFile { try? FileManager.default.removeItem(at: historyFile) }
        replaceUsageService(.live(reader: TodayUsageReader(historyFile: historyFile)))
    }

    /// A cleared pack remains useful only when a drawable card is still needed.
    func canBuy(pack: Int) -> Bool {
        guard snapshot.opening == nil, game.db.packs.indices.contains(pack), game.canAffordPack else { return false }
        return !game.progress(pack).cleared || game.db.packs[pack].cards.contains {
            game.wanted($0) && !game.isFusionOnly($0)
        }
    }
    @discardableResult func buy(pack: Int) -> Bool {
        guard canBuy(pack: pack) else { return false }
        let pulls = snapshot.game.buy(pack: pack, using: &rng)
        guard !pulls.isEmpty else { return false }
        snapshot.opening = LinuxOpening(pulls: pulls, title: game.db.packs[pack].name, pack: pack)
        persist(); publish(); return true
    }
    @discardableResult func openFree() -> Bool {
        guard snapshot.opening == nil else { return false }
        let pulls = snapshot.game.openFree(using: &rng)
        guard !pulls.isEmpty else { return false }
        snapshot.opening = LinuxOpening(pulls: pulls, title: L("무료 카드"))
        persist(); publish(); return true
    }
    @discardableResult func openFreePack() -> Bool {
        guard snapshot.opening == nil, let result = snapshot.game.openFreePack(using: &rng) else { return false }
        snapshot.opening = LinuxOpening(pulls: result.pulls, title: game.db.packs[result.pack].name, pack: result.pack, freePack: true)
        persist(); publish(); return true
    }
    func closeOpening() {
        guard snapshot.opening != nil else { return }; snapshot.opening = nil; publish()
    }
    @discardableResult func sell(_ cid: Int) -> Bool {
        guard game.copies(cid) > 1, snapshot.game.sell(cid) != nil else { return false }
        persist(); publish(); return true
    }
    @discardableResult func sellDuplicates() -> Int {
        let coins = snapshot.game.sellDuplicates()
        if coins > 0 { persist(); publish() }; return coins
    }
    func setAutoSellDuplicates(_ value: Bool) {
        guard game.state.autoSellDuplicates != value else { return }
        snapshot.game.state.autoSellDuplicates = value; persist(); publish()
    }
    func setEraLimit(_ value: String) {
        guard value.isEmpty || game.fullDB.eras.contains(where: { $0.name == value }), game.state.eraLimit != value else { return }
        snapshot.game.state.eraLimit = value; snapshot.opening = nil; pruneDexSelection(); persist(); publish()
    }
    func selectDexPack(_ index: Int?) {
        guard snapshot.dexPack != index else { return }
        snapshot.dexPack = index; snapshot.dexCard = nil; pruneDexSelection(); publish()
    }
    func selectDexCard(_ cid: Int?) {
        snapshot.dexCard = cid; pruneDexSelection(); publish()
    }
    /// Drop selections that no longer exist in the current era-limited database.
    private func pruneDexSelection() {
        if let pack = snapshot.dexPack, !game.db.packs.indices.contains(pack) { snapshot.dexPack = nil }
        guard let pack = snapshot.dexPack, let cid = snapshot.dexCard,
              game.db.packs[pack].cards.contains(cid), game.db.cards[cid] != nil else { snapshot.dexCard = nil; return }
    }
    @discardableResult func retrySave() -> Bool {
        guard snapshot.dirty else { return true }; persist(); publish(); return !snapshot.dirty
    }
    private func persist() {
        snapshot.game.unlockPartnerIfOwned()
        do { try store.save(game.state); snapshot.dirty = false; snapshot.saveError = nil }
        catch { snapshot.dirty = true; snapshot.saveError = error.localizedDescription }
    }
    private func publish() {
        guard snapshot != lastPublishedSnapshot else { return }
        snapshot.revision &+= 1
        lastPublishedSnapshot = snapshot
        onPublish?(snapshot)
    }
}

#endif
