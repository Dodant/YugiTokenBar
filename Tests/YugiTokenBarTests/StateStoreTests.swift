import Foundation
import Testing
@testable import YugiTokenBar

@Suite struct StateStoreTests {
    @Test func roundTrip() throws {
        let store = StateStore(url: tempDir().appendingPathComponent("state.json"))
        var state = GameState()
        state.coins = 42
        state.owned = [4007: 2, 4009: 1]
        state.claimedDate = "2026-10-01"
        state.claimedByProvider = ["codex": 5]
        state.log = [LogEntry(cid: 4007, source: "free", date: Date(timeIntervalSince1970: 1_000))]
        try store.save(state)
        #expect(store.load() == state)
    }

    @Test func olderSaveMissingKeysStillLoads() throws {
        let store = StateStore(url: tempDir().appendingPathComponent("state.json"))
        try Data(#"{"coins":7,"owned":{"4007":2}}"#.utf8).write(to: store.url)
        let state = store.load()
        #expect(state.coins == 7)
        #expect(state.owned == [4007: 2])
        #expect(state.unlocked == 1)
    }

    @Test func missingFileGivesFreshState() {
        let store = StateStore(url: tempDir().appendingPathComponent("state.json"))
        #expect(store.load() == GameState())
    }

    @Test func corruptFileRestoresBackupAndKeepsCorruptCopy() throws {
        let dir = tempDir()
        let store = StateStore(url: dir.appendingPathComponent("state.json"))
        var first = GameState()
        first.coins = 1
        try store.save(first)
        var second = GameState()
        second.coins = 2
        try store.save(second)  // .bak = first
        try Data("{깨짐".utf8).write(to: store.url)

        #expect(store.load().coins == 1)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(names.contains { $0.hasPrefix("state.corrupt-") })
    }
}
