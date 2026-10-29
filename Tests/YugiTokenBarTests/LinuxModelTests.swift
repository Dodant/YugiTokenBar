#if os(Linux)
import Foundation
import Testing
@testable import YugiTokenBar

private actor ControlledLinuxReader {
    var reads: [CheckedContinuation<LinuxUsageSnapshot, any Error>] = []
    var histories: [CheckedContinuation<UsageByDay, any Error>] = []
    var sinceValues: [String] = []
    func read(_ since: String) async throws -> LinuxUsageSnapshot {
        sinceValues.append(since)
        return try await withCheckedThrowingContinuation { reads.append($0) }
    }
    func history() async throws -> UsageByDay {
        try await withCheckedThrowingContinuation { histories.append($0) }
    }
    func finish(_ sample: LinuxUsageSnapshot) { reads.removeFirst().resume(returning: sample) }
    func failHistory() { histories.removeFirst().resume(throwing: CocoaError(.fileReadUnknown)) }
    func finishHistory(_ value: UsageByDay) { histories.removeFirst().resume(returning: value) }
    var readCount: Int { sinceValues.count }
    var historyCount: Int { histories.count }
    nonisolated var service: LinuxUsageService {
        .init(read: { since, _ in try await self.read(since) }, history: { _ in try await self.history() })
    }
}

@MainActor private func until(_ condition: () async -> Bool) async {
    for _ in 0..<2000 {
        if await condition() { return }
        try? await Task.sleep(for: .milliseconds(1))
    }
    Issue.record("Timed out waiting for asynchronous model work")
}

@MainActor private func makeLinuxModel(state: GameState = GameState(), db: CardDB? = nil,
                                      store: StateStore? = nil, reader: ControlledLinuxReader) -> (LinuxModel, StateStore) {
    let target = store ?? StateStore(url: tempDir().appendingPathComponent("state.json"))
    return (LinuxModel(game: Game(db: db ?? makeDB([[(1, 1), (2, 1), (3, 1)]]), state: state),
                       store: target, service: reader.service), target)
}

@MainActor private func receive(_ model: LinuxModel, _ predicate: () -> Bool) async {
    await until { model.drainEvents(); return predicate() }
}

@Suite @MainActor struct LinuxModelTests {
    @Test func currentGameClaimAndCoalescing() async {
        let reader = ControlledLinuxReader()
        var state = GameState(); state.coins = 2000
        let (model, _) = makeLinuxModel(state: state, reader: reader)
        model.start(); model.start(); model.refresh(); model.refresh(); model.refresh()
        await until { await reader.readCount == 1 }
        #expect(model.buy(pack: 0))
        let owned = model.game.state.owned
        await reader.finish(.init(date: "2026-10-19", byProvider: ["codex": 20_000], earlier: ["2026-10-05": ["codex": 10_000]]))
        await receive(model) { !model.snapshot.refreshing }
        #expect(model.game.state.coins == 1003)
        #expect(model.game.state.owned == owned)
        await until { await reader.readCount == 2 }
        await reader.finish(.init(date: "2026-10-19", byProvider: ["codex": 20_000], earlier: ["2026-10-05": ["codex": 10_000]]))
        await receive(model) { !model.readInFlight }
        #expect(model.game.state.coins == 1003)
        #expect(await reader.readCount == 2)
        model.stop()
    }

    @Test func firstEmptyReadDoesNotCreateLedger() async {
        let reader = ControlledLinuxReader(); let (model, store) = makeLinuxModel(reader: reader)
        model.start(); await until { await reader.readCount == 1 }
        #expect(await reader.sinceValues.first != nil)
        await reader.finish(.init(date: "2026-10-19"))
        await receive(model) { !model.snapshot.refreshing }
        #expect(model.game.state.claimedDate == nil)
        #expect(!FileManager.default.fileExists(atPath: store.url.path))
        model.stop()
    }

    @Test func unchangedPeriodicReadDoesNotPublishOrWrite() async throws {
        let reader = ControlledLinuxReader(); let (model, store) = makeLinuxModel(reader: reader)
        let sample = LinuxUsageSnapshot(date: "2026-10-19", byProvider: ["codex": 10_000])
        model.start(); await until { await reader.readCount == 1 }; await reader.finish(sample)
        await receive(model) { !model.snapshot.refreshing }
        let revision = model.snapshot.revision
        let attributes = try FileManager.default.attributesOfItem(atPath: store.url.path)
        var publishes = 0; model.onPublish = { _ in publishes += 1 }
        model.refresh(); await until { await reader.readCount == 2 }; await reader.finish(sample)
        for _ in 0..<20 { try? await Task.sleep(for: .milliseconds(1)); model.drainEvents() }
        #expect(model.snapshot.revision == revision); #expect(publishes == 0)
        let next = try FileManager.default.attributesOfItem(atPath: store.url.path)
        #expect(attributes[.modificationDate] as? Date == next[.modificationDate] as? Date)
        model.stop()
    }

    @Test func oldCompletionCannotClearReplacementBusy() async {
        let old = ControlledLinuxReader(), new = ControlledLinuxReader()
        let (model, _) = makeLinuxModel(reader: old)
        model.start(); await until { await old.readCount == 1 }
        model.replaceUsageService(new.service)
        await until { await new.readCount == 1 }
        await old.finish(.init(date: "2026-10-19", byProvider: ["codex": 900_000]))
        for _ in 0..<10 { await Task.yield(); model.drainEvents() }
        #expect(model.snapshot.refreshing); #expect(model.game.state.coins == 0)
        await new.finish(.init(date: "2026-10-19", byProvider: ["codex": 20_000]))
        await receive(model) { !model.snapshot.refreshing }
        #expect(model.game.state.coins == 2); model.stop()
    }

    @Test func stopRestartDropsOldInboxAndUsesNewEpoch() async {
        let reader = ControlledLinuxReader(); let (model, _) = makeLinuxModel(reader: reader)
        model.start(); await until { await reader.readCount == 1 }
        let epoch = model.lifecycleEpoch
        model.stop(); model.stop(); model.start()
        await until { await reader.readCount == 2 }
        #expect(model.lifecycleEpoch > epoch)
        await reader.finish(.init(date: "2026-10-19", byProvider: ["codex": 500_000]))
        for _ in 0..<10 { await Task.yield(); model.drainEvents() }
        #expect(model.snapshot.refreshing); #expect(model.game.state.coins == 0)
        await reader.finish(.init(date: "2026-10-19", byProvider: ["codex": 10_000]))
        await receive(model) { !model.snapshot.refreshing }
        #expect(model.game.state.coins == 1); model.stop()
    }

    @Test func failedSavePreservesMemoryAndIdenticalReadRetries() async throws {
        let directory = tempDir(), blocked = directory.appendingPathComponent("blocked")
        try Data().write(to: blocked)
        let reader = ControlledLinuxReader()
        let (model, store) = makeLinuxModel(store: StateStore(url: blocked.appendingPathComponent("state.json")), reader: reader)
        let sample = LinuxUsageSnapshot(date: "2026-10-19", byProvider: ["codex": 10_000])
        model.start(); await until { await reader.readCount == 1 }; await reader.finish(sample)
        await receive(model) { !model.snapshot.refreshing }
        #expect(model.snapshot.dirty); #expect(model.snapshot.saveError != nil); #expect(model.game.state.coins == 1)
        let revision = model.snapshot.revision
        #expect(!model.retrySave())
        #expect(model.snapshot.revision == revision)
        model.refresh(); await until { await reader.readCount == 2 }; await reader.finish(sample)
        await receive(model) { !model.readInFlight }
        #expect(model.snapshot.revision == revision)
        try FileManager.default.removeItem(at: blocked)
        model.refresh(); await until { await reader.readCount == 3 }; await reader.finish(sample)
        await receive(model) { !model.snapshot.dirty }
        #expect(model.snapshot.saveError == nil); #expect(store.load().coins == 1); model.stop()
    }

    @Test func guardsAndWantedClearedPack() {
        let reader = ControlledLinuxReader()
        let db = oneBoxDB([1: overframeCard("test")])
        var state = GameState(); state.coins = 3000; state.owned[1] = 1
        let (model, _) = makeLinuxModel(state: state, db: db, reader: reader)
        #expect(model.game.progress(0).cleared); #expect(!model.game.progress(0).done)
        #expect(!model.buy(pack: -1)); #expect(!model.buy(pack: 1)); #expect(!model.sell(1))
        #expect(model.buy(pack: 0)); #expect(!model.buy(pack: 0))
        #expect(!model.openFree()); #expect(!model.openFreePack())
        model.closeOpening()
        #expect(model.buy(pack: 0)); #expect(model.game.progress(0).done)
        #expect(!model.buy(pack: 0)); #expect(model.sell(1)); #expect(model.game.showsOverframe(1))
    }

    @Test func flipTurnsCardsAndLeavesThePackRareSlotLast() throws {
        var state = GameState(); state.coins = 3000; state.pendingFree = 2
        let (model, _) = makeLinuxModel(state: state, reader: ControlledLinuxReader())
        model.flip(0); model.flipAll()  // nothing open: no-ops
        #expect(model.buy(pack: 0))
        let last = try #require(model.snapshot.opening?.pulls.indices.last)
        model.flip(1); model.flip(99)
        #expect(model.snapshot.opening?.flipped == [1]); #expect(model.snapshot.opening?.lateFlip == nil)
        model.flipAll()
        #expect(model.snapshot.opening?.allFlipped == true); #expect(model.snapshot.opening?.lateFlip == last)
        model.closeOpening(); #expect(model.openFree())
        model.flipAll()
        #expect(model.snapshot.opening?.allFlipped == true); #expect(model.snapshot.opening?.lateFlip == nil)  // free cards: no rare slot
    }

    @Test func openAllShowsEveryFreeCardAndPackFaceUp() {
        var state = GameState(); state.pendingFree = Balance.freeOpenAllMin + 1; state.freePacks = 3
        let (model, _) = makeLinuxModel(state: state, reader: ControlledLinuxReader())
        #expect(model.openFree(all: true))
        #expect(model.snapshot.opening?.pulls.count == Balance.freeOpenAllMin + 1); #expect(model.snapshot.opening?.allFlipped == true)
        #expect(!model.openAllFreePacks())  // one opening at a time
        model.closeOpening(); #expect(model.openAllFreePacks())
        #expect(model.game.state.freePacks == 0); #expect(model.snapshot.opening?.allFlipped == true)
        model.closeOpening(); #expect(!model.openAllFreePacks())
    }

    @Test func dexSelectionValidatesAndFollowsEraLimit() {
        let reader = ControlledLinuxReader()
        // 12 packs: DM 0..<11, GX 11..<12; each pack holds cid = index + 1.
        let (model, _) = makeLinuxModel(db: makeDB((0..<12).map { [($0 + 1, 1)] }, era: { $0 < 11 ? "DM" : "GX" }), reader: reader)
        model.selectDexPack(99); #expect(model.snapshot.dexPack == nil)
        model.selectDexPack(0); model.selectDexCard(2)
        #expect(model.snapshot.dexPack == 0); #expect(model.snapshot.dexCard == nil) // cid 2 is not in pack 0
        model.selectDexCard(1); #expect(model.snapshot.dexCard == 1)
        model.selectDexPack(5); #expect(model.snapshot.dexCard == nil) // changing pack drops the card
        model.setEraLimit("DM"); #expect(model.snapshot.dexPack == 5) // still valid
        model.selectDexCard(6); model.setEraLimit("GX")
        #expect(model.snapshot.dexPack == 5 && model.snapshot.dexCard == 6)
        model.selectDexPack(11); model.selectDexCard(12)
        #expect(model.snapshot.dexCard == 12)
        model.setEraLimit("DM")
        #expect(model.snapshot.dexPack == nil); #expect(model.snapshot.dexCard == nil)
        model.selectDexPack(nil); #expect(model.snapshot.dexPack == nil)
    }

    @Test func startupUnlockPreservesHiddenPreferences() async {
        let reader = ControlledLinuxReader(); let db = oneBoxDB([1: overframeCard("test")])
        var state = GameState(); state.owned[1] = 3; state.partnerEnabled = false
        state.partnerUnlocked = true; state.animationsOff = true; state.partnerSize = 200
        let (model, store) = makeLinuxModel(state: state, db: db, reader: reader)
        model.start(); await until { await reader.readCount == 1 }
        #expect(model.game.showsOverframe(1)); #expect(!store.load().partnerEnabled)
        #expect(store.load().partnerSize == 200); #expect(store.load().animationsOff)
        model.stop(); await reader.finish(.init(date: "2026-10-19"))
    }

    @Test func historySamplingErrorsAndReaderReset() async {
        let reader = ControlledLinuxReader(), next = ControlledLinuxReader()
        let (model, _) = makeLinuxModel(reader: reader)
        let now = Date(timeIntervalSince1970: 1_792_396_800)
        let day = LocalUsageReader.localDayFormatter().string(from: now)
        model.start(); await until { await reader.readCount == 1 }
        await reader.finish(.init(date: day)); await receive(model) { !model.snapshot.refreshing }
        model.loadHistory(now: now); await until { await reader.historyCount == 1 }
        await reader.failHistory(); await receive(model) { !model.snapshot.loadingHistory }
        #expect(model.snapshot.historyError != nil); #expect(model.snapshot.historyDate == nil)
        model.loadHistory(now: now); await until { await reader.historyCount == 1 }
        await reader.finishHistory(["2026-10-01": [:]])
        await receive(model) { !model.snapshot.loadingHistory }
        #expect(model.snapshot.historyDate == day); #expect(model.snapshot.historyError == nil)
        model.replaceUsageService(next.service, now: now)
        #expect(model.snapshot.history == nil); #expect(model.snapshot.historyDate == nil)
        await until { await next.readCount == 1 }
        await next.finish(.init(date: "later")); await receive(model) { !model.snapshot.refreshing }
        #expect(model.snapshot.todayDate == "later"); model.stop()
    }

    @Test func historyRequestsDedupeRollOverMidnightAndDropStaleResults() async {
        let reader = ControlledLinuxReader(), next = ControlledLinuxReader()
        let (model, _) = makeLinuxModel(reader: reader)
        let now = Date(timeIntervalSince1970: 1_792_396_800)
        let tomorrow = now.addingTimeInterval(86_400)
        model.start(); await until { await reader.readCount == 1 }
        model.loadHistory(now: now); model.loadHistory(now: now); model.loadHistory(now: now)
        await until { await reader.historyCount == 1 }
        for _ in 0..<10 { await Task.yield() }
        #expect(await reader.historyCount == 1); #expect(model.snapshot.loadingHistory)
        await reader.finishHistory(["2026-10-01": ["codex": usageSum(5)]])
        await receive(model) { !model.snapshot.loadingHistory }
        model.loadHistory(now: now) // same day: kept
        for _ in 0..<10 { await Task.yield() }
        #expect(await reader.historyCount == 0); #expect(!model.snapshot.loadingHistory)
        model.loadHistory(now: tomorrow) // midnight passed: request again
        await until { await reader.historyCount == 1 }
        #expect(model.snapshot.loadingHistory)
        model.replaceUsageService(next.service, now: now) // root change / import while pending
        #expect(model.snapshot.history == nil); #expect(!model.snapshot.loadingHistory)
        model.loadHistory(now: now); await until { await next.historyCount == 1 }
        await reader.finishHistory(["2026-10-02": ["codex": usageSum(9)]]) // late result of the old service
        for _ in 0..<10 { await Task.yield(); model.drainEvents() }
        #expect(model.snapshot.history == nil); #expect(model.snapshot.loadingHistory)
        await next.finishHistory(["2026-10-03": ["codex": usageSum(7)]])
        await receive(model) { !model.snapshot.loadingHistory }
        #expect(model.snapshot.history?.keys.sorted() == ["2026-10-03"]); model.stop()
    }

    @Test func inboxCloseDropsQueuedAndLateValues() {
        let inbox = LinuxInbox()
        inbox.send(.usage(1, 1, 1, .success(.init(date: "today"))))
        inbox.close(); inbox.send(.usage(2, 1, 1, .success(.init(date: "today"))))
        #expect(inbox.drain().isEmpty)
    }
}

@Suite @MainActor struct LinuxTransferTests {
    private func envelopeFile(_ state: GameState, schema: Int? = nil, in dir: URL = tempDir()) throws -> URL {
        var envelope = SaveEnvelope(appVersion: "9.9.9", exportedAt: Date(timeIntervalSince1970: 1_700_000_000), state: state)
        if let schema { envelope.schema = schema }
        let url = dir.appendingPathComponent("incoming.json")
        try envelope.encoded().write(to: url); return url
    }

    @Test func exportRoundTripsThroughEnvelopeAndGIOWrite() throws {
        var state = GameState(); state.coins = 42; state.owned = [1: 2]
        let (model, _) = makeLinuxModel(state: state, reader: ControlledLinuxReader())
        let decoded = try SaveEnvelope.decode(model.exportedSave())
        #expect(decoded.state == model.game.state)
        let target = tempDir().appendingPathComponent(SaveEnvelope.fileName(Date()))
        try Data("old".utf8).write(to: target)
        model.export(to: target)
        #expect(model.snapshot.transferError == nil); #expect(model.snapshot.transferMessage != nil)
        #expect(try SaveEnvelope.decode(Data(contentsOf: target)).state == model.game.state)
        model.export(to: target.deletingLastPathComponent().appendingPathComponent("missing/out.json"))
        #expect(model.snapshot.transferError != nil); #expect(model.snapshot.transferMessage == nil)
    }

    @Test func prepareImportValidatesBeforeOfferingReplacement() throws {
        let (model, _) = makeLinuxModel(reader: ControlledLinuxReader())
        let dir = tempDir(), big = dir.appendingPathComponent("big.json")
        try Data(repeating: 0x20, count: SaveEnvelope.maxFileBytes + 1).write(to: big)
        model.prepareImport(at: big)
        #expect(model.snapshot.pendingImport == nil)
        #expect(model.snapshot.transferError?.contains(SaveTransferError.tooLarge.localizedDescription) == true)
        let plain = dir.appendingPathComponent("plain.json"); try Data("{\"coins\": 5}".utf8).write(to: plain)
        model.prepareImport(at: plain)
        #expect(model.snapshot.transferError?.contains(SaveTransferError.notASaveFile.localizedDescription) == true)
        model.prepareImport(at: try envelopeFile(GameState(), schema: GameState.schemaVersion + 1))
        #expect(model.snapshot.transferError?.contains(SaveTransferError.newerSchema.localizedDescription) == true)
        model.prepareImport(at: dir.appendingPathComponent("absent.json"))
        #expect(model.snapshot.transferError != nil); #expect(model.snapshot.pendingImport == nil)
        var incoming = GameState(); incoming.coins = 9
        model.prepareImport(at: try envelopeFile(incoming))
        #expect(model.snapshot.transferError == nil)
        #expect(model.snapshot.pendingImport?.envelope.state.coins == 9)
        #expect(model.snapshot.pendingImport?.fileName == "incoming.json")
    }

    @Test func confirmImportKeepsLedgerBacksUpSavesAndDropsStaleRead() async throws {
        let reader = ControlledLinuxReader()
        var local = GameState()
        local.coins = 5; local.claimedDate = "2026-10-19"; local.claimedByProvider = ["codex": 5]
        local.overframes = [1]; local.partnerUnlocked = true; local.partnerEnabled = false
        let (model, store) = makeLinuxModel(state: local, db: oneBoxDB([1: overframeCard("a"), 2: card("b")]), reader: reader)
        model.selectDexPack(0); model.selectDexCard(2)
        model.start(); await until { await reader.readCount == 1 }
        var incoming = GameState()
        incoming.coins = 77; incoming.owned = [2: 3]; incoming.claimedDate = "2026-01-01"
        incoming.claimedByProvider = ["claude_code": 99]; incoming.overframes = [999]; incoming.partnerSize = 200
        model.prepareImport(at: try envelopeFile(incoming))
        let generation = model.stateGeneration
        var published: [LinuxSnapshot] = []
        model.onPublish = { published.append($0) }
        #expect(model.confirmImport())
        let state = model.game.state
        #expect(state.coins == 77); #expect(state.owned == [2: 3])
        #expect(state.claimedDate == "2026-10-19"); #expect(state.claimedByProvider == ["codex": 5])
        #expect(state.overframes == [1]); #expect(state.partnerUnlocked); #expect(!state.partnerEnabled)
        #expect(state.partnerSize == 128)
        #expect(model.stateGeneration == generation &+ 1); #expect(model.snapshot.pendingImport == nil)
        #expect(!published.isEmpty); #expect(model.snapshot.transferError == nil)
        #expect(store.load() == state)
        let folder = store.url.deletingLastPathComponent()
        let backups = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasPrefix("state.import-backup-") }
        #expect(backups.count == 1)
        #expect(model.snapshot.transferMessage?.contains(backups[0]) == true)
        #expect(try SaveEnvelope.decode(Data(contentsOf: folder.appendingPathComponent(backups[0]))).state == local)
        #expect(model.snapshot.dexCard == 2)
        await until { await reader.readCount == 2 }
        await reader.finish(.init(date: "2026-10-20", byProvider: ["codex": 50_000])) // read that predates the import
        for _ in 0..<10 { await Task.yield(); model.drainEvents() }
        #expect(model.game.state == state)
        await reader.finish(.init(date: "2026-10-19")); await receive(model) { !model.snapshot.refreshing }
        #expect(model.game.state.claimedDate == "2026-10-19"); model.stop()
    }

    @Test func failedImportKeepsEverythingButTheErrorLine() throws {
        let directory = tempDir(), blocked = directory.appendingPathComponent("blocked")
        try Data().write(to: blocked)
        var local = GameState(); local.coins = 2000
        let (model, _) = makeLinuxModel(state: local, store: StateStore(url: blocked.appendingPathComponent("state.json")),
                                        reader: ControlledLinuxReader())
        #expect(model.buy(pack: 0))
        var incoming = GameState(); incoming.coins = 3
        model.prepareImport(at: try envelopeFile(incoming))
        let before = model.game.state, opening = model.snapshot.opening
        let pending = model.snapshot.pendingImport, generation = model.stateGeneration
        #expect(!model.confirmImport())
        #expect(model.game.state == before); #expect(model.snapshot.opening == opening)
        #expect(model.snapshot.pendingImport == pending); #expect(model.stateGeneration == generation)
        #expect(model.snapshot.transferError != nil); #expect(model.snapshot.transferMessage == nil)
    }

    @Test func cancelImportOnlyClearsPending() throws {
        var local = GameState(); local.coins = 8
        let (model, _) = makeLinuxModel(state: local, reader: ControlledLinuxReader())
        model.prepareImport(at: try envelopeFile(GameState()))
        let generation = model.stateGeneration
        model.cancelImport()
        #expect(model.snapshot.pendingImport == nil); #expect(model.game.state == local)
        #expect(model.stateGeneration == generation); #expect(model.snapshot.transferError == nil)
        #expect(!model.confirmImport())
    }

    @Test func macRoundTripKeepsHiddenFieldsAndLocalLedger() throws {
        var mac = GameState()
        mac.coins = 123; mac.coinRemainder = 4; mac.owned = [1: 1, 3: 2]; mac.favorites = [2]
        mac.partnerUnlocked = true; mac.partnerEnabled = false; mac.partnerSize = 192
        mac.partnerOrigin = CGPoint(x: 10, y: 20); mac.eraLimit = "GX"
        mac.decks = [Deck(name: "덱", cards: [1: 1, 3: 2])]
        mac.claimedDate = "2026-09-01"; mac.claimedByProvider = ["grok": 7]; mac.lastBoughtPid = "p0"
        var local = GameState(); local.claimedDate = "2026-10-19"; local.claimedByProvider = ["codex": 1]
        let (model, _) = makeLinuxModel(state: local, reader: ControlledLinuxReader())
        model.prepareImport(at: try envelopeFile(mac))
        #expect(model.confirmImport())
        var expected = mac.withLedger(of: local)
        expected.overframes = []
        #expect(model.game.state == expected)
        #expect(model.game.state.partnerUnlocked); #expect(model.game.state.partnerOrigin == nil)
        #expect(model.game.state.decks == mac.decks)
    }
}

#endif
