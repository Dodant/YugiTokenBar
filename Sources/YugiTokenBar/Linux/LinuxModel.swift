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
    /// Tests inject a fake; nothing outside the settings screen's update check talks to GitHub.
    var latestVersionFetcher: @Sendable () async -> String? = { await AppInfo.fetchLatestVersion() }
    /// Default desktop handler; tests inject a fake so no real application is launched.
    var opener: (URL) -> String? = { LinuxSystemActions.open($0) }
    var usageHistoryFile: URL? = TodayUsageReader.defaultHistoryFile
    var scanRootsDebounce: Duration = .milliseconds(800)
    private var scanTask: Task<Void, Never>?
    private var updateTask: Task<Void, Never>?
    private var updateChecked = false

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
        updateTask?.cancel(); updateTask = nil; scanTask?.cancel(); scanTask = nil
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

    /// Same policy as the macOS Settings check (published stable releases only, AppInfo.releaseVersion),
    /// run at most once per launch after a result; a failed or cancelled check may be retried.
    func checkForUpdate() {
        guard running, !updateChecked, updateTask == nil else { return }
        let epoch = lifecycleEpoch, inbox = inbox, fetch = latestVersionFetcher
        updateTask = Task.detached {
            let latest = await fetch()
            inbox.send(.update(epoch, latest))
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
            case let .update(epoch, latest):
                guard running, epoch == lifecycleEpoch else { continue }
                updateTask = nil
                guard let latest else { continue }
                updateChecked = true; snapshot.latestVersion = latest; publish()
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
    /// `all` opens every pending free card face up, like the macOS [All].
    @discardableResult func openFree(all: Bool = false) -> Bool {
        guard snapshot.opening == nil else { return false }
        let pulls = snapshot.game.openFree(limit: all ? .max : Balance.freeOpenBatch, using: &rng)
        guard !pulls.isEmpty else { return false }
        snapshot.opening = LinuxOpening(pulls: pulls, title: L("무료 카드"), flipped: all ? Set(pulls.indices) : [])
        persist(); publish(); return true
    }
    /// Opens every free pack, including ones won on the way, face up in one grid.
    @discardableResult func openAllFreePacks() -> Bool {
        guard snapshot.opening == nil else { return false }
        var pulls: [Pull] = [], opened = 0
        while let (_, p) = snapshot.game.openFreePack(using: &rng) { pulls += p; opened += 1 }
        guard opened > 0 else { return false }
        snapshot.opening = LinuxOpening(pulls: pulls, title: L("무료 팩 %lld개", .int(opened)), flipped: Set(pulls.indices))
        persist(); publish(); return true
    }
    @discardableResult func openFreePack() -> Bool {
        guard snapshot.opening == nil, let result = snapshot.game.openFreePack(using: &rng) else { return false }
        snapshot.opening = LinuxOpening(pulls: result.pulls, title: game.db.packs[result.pack].name, pack: result.pack, freePack: true)
        persist(); publish(); return true
    }
    func flip(_ index: Int) {
        guard var opening = snapshot.opening, opening.pulls.indices.contains(index), !opening.flipped.contains(index) else { return }
        opening.flipped.insert(index); snapshot.opening = opening; publish()
    }
    /// The pack's last card is its rare slot, turned last like on macOS (the delay itself is CSS).
    func flipAll() {
        guard var opening = snapshot.opening, !opening.allFlipped else { return }
        if opening.pack != nil, let rare = opening.pulls.indices.last, !opening.flipped.contains(rare) { opening.lateFlip = rare }
        opening.flipped = Set(opening.pulls.indices); snapshot.opening = opening; publish()
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
    func open(_ url: URL) {
        recordSystemError(opener(url).map { L("열지 못했어요: %@", .text($0)) })
    }
    func openSaveFolder() { open(store.url.deletingLastPathComponent()) }

    /// Same storage as macOS (UserDefaults customScanRoots.<id>). The reader caches are dropped at once;
    /// the fresh reader is built after typing pauses, because it also clears the day history file.
    func setScanRoots(_ value: String, provider: String) {
        UserDefaults.standard.set(value, forKey: CustomScanRoots.defaultsKey(for: provider))
        LocalUsageReader.invalidateProjectRootsCache()
        scanTask?.cancel()
        let delay = scanRootsDebounce
        scanTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.scanTask = nil
            if self.running { self.resetUsageReader(historyFile: self.usageHistoryFile) }
        }
    }

    /// Settings status lines; a GIO open error stays visible until the next attempt.
    func recordSystemError(_ message: String?) {
        guard snapshot.systemError != message else { return }; snapshot.systemError = message; publish()
    }
    func recordRestartError(_ message: String?) {
        guard snapshot.restartError != message else { return }; snapshot.restartError = message; publish()
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
    func exportedSave() throws -> Data {
        try SaveEnvelope(appVersion: AppInfo.currentVersion, exportedAt: Date(), state: game.state).encoded()
    }
    func export(to url: URL) {
        do {
            try LinuxSaveTransfer.write(try exportedSave(), to: url)
            snapshot.transferMessage = L("내보냈어요: %@", .text(url.lastPathComponent)); snapshot.transferError = nil
        } catch {
            snapshot.transferMessage = nil
            snapshot.transferError = L("내보내지 못했어요: %@", .text(error.localizedDescription))
        }
        publish()
    }
    func prepareImport(at url: URL) {
        snapshot.transferMessage = nil; snapshot.transferError = nil; snapshot.pendingImport = nil
        do { snapshot.pendingImport = LinuxPendingImport(envelope: try LinuxSaveTransfer.readEnvelope(at: url), fileName: url.lastPathComponent) }
        catch { snapshot.transferError = L("가져오지 못했어요: %@", .text(error.localizedDescription)) }
        publish()
    }
    func cancelImport() {
        guard snapshot.pendingImport != nil else { return }; snapshot.pendingImport = nil; publish()
    }
    /// Mirrors AppModel.importSave: memory and the usage generation change only after the save is written.
    @discardableResult func confirmImport() -> Bool {
        guard let pending = snapshot.pendingImport else { return false }
        do {
            let backup = try store.backupBeforeImport(game.state, appVersion: AppInfo.currentVersion)
            var imported = game
            imported.state = pending.envelope.state.withLedger(of: game.state)
            imported.state.overframes = imported.state.overframes.filter(imported.hasOverframe)
            imported.unlockOwnedOverframes()
            imported.unlockPartnerIfOwned()
            try store.save(imported.state)
            snapshot.game = imported; snapshot.opening = nil; pruneDexSelection()
            snapshot.dirty = false; snapshot.saveError = nil; snapshot.pendingImport = nil
            snapshot.transferError = nil
            snapshot.transferMessage = L("이전 세이브는 %@로 백업했어요.", .text(backup.lastPathComponent))
            publish()
            // The kept ledger decides what a fresh read credits; stale results from before the import are dropped.
            replaceUsageService(service)
            return true
        } catch {
            snapshot.transferMessage = nil
            snapshot.transferError = L("가져오지 못했어요: %@", .text(error.localizedDescription))
            publish(); return false
        }
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
