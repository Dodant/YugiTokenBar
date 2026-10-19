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

    @Test func dexSelectionValidatesAndFollowsEraLimit() {
        let reader = ControlledLinuxReader()
        // 12 packs: DM 0..<11, GX 11..<12; each pack holds cid = index + 1.
        let (model, _) = makeLinuxModel(db: makeDB((0..<12).map { [($0 + 1, 1)] }), reader: reader)
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

    @Test func inboxCloseDropsQueuedAndLateValues() {
        let inbox = LinuxInbox()
        inbox.send(.usage(1, 1, 1, .success(.init(date: "today"))))
        inbox.close(); inbox.send(.usage(2, 1, 1, .success(.init(date: "today"))))
        #expect(inbox.drain().isEmpty)
    }
}

#endif
