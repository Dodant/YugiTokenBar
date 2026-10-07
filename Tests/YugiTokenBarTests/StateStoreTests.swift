import Foundation
import Testing
@testable import YugiTokenBar

@Suite struct StateStoreTests {
    /// 저장이 실패하면 모델이 이유를 들고 있다가(경고 표시), 다음 저장이 되면 지운다
    @MainActor @Test func modelReportsSaveFailureUntilNextSuccess() throws {
        let dir = tempDir()
        let blocker = dir.appendingPathComponent("save")
        try Data().write(to: blocker)  // 폴더 자리에 파일이 있어 폴더를 만들 수 없다
        let model = AppModel(db: makeDB([[(1, 1)]]), store: StateStore(url: blocker.appendingPathComponent("state.json")),
                             partner: PartnerModel(sheet: nil))
        model.toggleFavorite(1)
        #expect(model.saveError != nil)
        try FileManager.default.removeItem(at: blocker)
        model.toggleFavorite(1)
        #expect(model.saveError == nil)
    }

    /// 저장 실패 경고가 떠 있어도 가져오기 저장이 성공하면 사라진다
    @MainActor @Test func importSaveClearsSaveError() throws {
        let dir = tempDir()
        let url = dir.appendingPathComponent("state.json")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data().write(to: url.appendingPathComponent("x"))  // 비어 있지 않은 폴더가 파일 자리를 막는다
        let model = AppModel(db: makeDB([[(1, 1)]]), store: StateStore(url: url), partner: PartnerModel(sheet: nil))
        model.toggleFavorite(1)
        #expect(model.saveError != nil)
        try FileManager.default.removeItem(at: url)
        _ = try model.importSave(SaveEnvelope(appVersion: "0.4.3", exportedAt: Date(), state: GameState()))
        #expect(model.saveError == nil)
    }

    @Test func roundTrip() throws {
        let store = StateStore(url: tempDir().appendingPathComponent("state.json"))
        var state = GameState()
        state.coins = 42
        state.owned = [4007: 2, 4009: 1]
        state.claimedDate = "2026-10-01"
        state.claimedByProvider = ["codex": 5]
        state.favorites = [4007, 4100]
        state.decks = [Deck(name: "드래곤", cards: [4007: 2])]
        state.log = [LogEntry(cid: 4007, source: "free", date: Date(timeIntervalSince1970: 1_000))]
        try store.save(state)
        #expect(store.load() == state)
    }

    /// 모든 필드를 기본값과 다르게 채워 저장 → 읽기. `init(from:)` 에 새 필드 한 줄을 빠뜨리면 그 값이 실행마다 기본값으로 돌아가는데,
    /// 그걸 잡는다. 새 필드를 추가하면 아래 채우기에도 넣어야 첫 검사가 통과한다.
    @Test func everyFieldSurvivesSaveAndLoad() throws {
        var state = GameState()
        state.coins = 1
        state.coinRemainder = 2
        state.dropProgress = 3
        state.owned = [4007: 2]
        state.claimedDate = "2026-10-01"
        state.claimedByProvider = ["codex": 5]
        state.pendingFree = 4
        state.packStamp = 5
        state.freePacks = 6
        state.favorites = [4007]
        state.autoSellDuplicates = true
        state.fusionOnly = true
        state.animationsOff = true
        state.eraLimit = "DM"
        state.partnerUnlocked = true
        state.partnerEnabled = false
        state.partnerSize = 200
        state.partnerOrigin = CGPoint(x: 10, y: 20)
        state.decks = [Deck(name: "덱", cards: [4007: 1])]
        state.log = [LogEntry(cid: 4007, source: LogEntry.free, date: Date(timeIntervalSince1970: 1_000))]
        state.lastBoughtPid = "P1"

        let defaults = Dictionary(uniqueKeysWithValues: Mirror(reflecting: GameState()).children.map { ($0.label!, "\($0.value)") })
        let unfilled = Mirror(reflecting: state).children.filter { defaults[$0.label!] == "\($0.value)" }.map { $0.label! }
        #expect(unfilled.isEmpty, "기본값 그대로인 필드: \(unfilled)")

        let store = StateStore(url: tempDir().appendingPathComponent("state.json"))
        try store.save(state)
        #expect(store.load() == state)
    }

    @Test func olderSaveMissingKeysStillLoads() throws {
        let store = StateStore(url: tempDir().appendingPathComponent("state.json"))
        try Data(#"{"coins":7,"owned":{"4007":2}}"#.utf8).write(to: store.url)
        let state = store.load()
        #expect(state.coins == 7)
        #expect(state.owned == [4007: 2])
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

    @Test func saveAfterRecoveryKeepsGoodBackup() throws {
        let store = StateStore(url: tempDir().appendingPathComponent("state.json"))
        var first = GameState()
        first.coins = 1
        try store.save(first)
        var second = GameState()
        second.coins = 2
        try store.save(second)  // .bak = first
        try Data("{깨짐".utf8).write(to: store.url)

        try store.save(store.load())  // 복구본(first) 저장: 손상된 원본으로 .bak을 덮으면 안 된다

        let bak = try JSONDecoder().decode(GameState.self, from: Data(contentsOf: store.backupURL))
        #expect(bak.coins == 1)
    }
}
