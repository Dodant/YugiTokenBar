import Foundation
import Testing
@testable import YugiTokenBar

@Suite struct SaveTransferTests {
    @Test func envelopeRoundTrip() throws {
        var state = GameState()
        state.coins = 9
        state.owned = [4007: 3]
        let envelope = SaveEnvelope(appVersion: "0.2.0", exportedAt: Date(timeIntervalSince1970: 1_000), state: state)
        #expect(try SaveEnvelope.decode(envelope.encoded()) == envelope)
    }

    @Test func rejectsPlainStateAndNewerSchema() throws {
        // GameState 자체는 이 JSON 을 "성공"으로 읽는다 → 봉투가 막아야 한다
        #expect(throws: SaveTransferError.notASaveFile) { try SaveEnvelope.decode(Data(#"{"coins":7}"#.utf8)) }
        let newer = #"{"format":"yugitokenbar.save","schema":99}"#
        #expect(throws: SaveTransferError.newerSchema) { try SaveEnvelope.decode(Data(newer.utf8)) }
    }

    @MainActor @Test func importBacksUpAndKeepsLocalLedger() throws {
        let dir = tempDir()
        let store = StateStore(url: dir.appendingPathComponent("state.json"))
        var local = GameState()
        local.coins = 1
        local.claimedDate = "2026-10-02"
        local.claimedByProvider = ["claude": 500]
        try store.save(local)
        let model = AppModel(db: makeDB([[(1, 1)]]), store: store)

        var incoming = GameState()
        incoming.coins = 77
        incoming.owned = [1: 2]
        incoming.claimedDate = "2026-09-30"
        incoming.claimedByProvider = ["claude": 9]
        let backup = try model.importSave(SaveEnvelope(appVersion: "0.2.0", exportedAt: Date(), state: incoming))

        #expect(backup.deletingLastPathComponent().path == dir.path)
        #expect(try SaveEnvelope.decode(Data(contentsOf: backup)).state == local)
        let saved = store.load()
        #expect(saved.coins == 77 && saved.owned == [1: 2])
        #expect(saved.claimedDate == "2026-10-02" && saved.claimedByProvider == ["claude": 500])
        #expect(model.game.state == saved)
    }

    @Test func changelogVersionAndCompare() {
        let text = "# 패치노트\n\n## 0.10.0 — 2026-10-02\n- x\n## 0.9.1\n"
        #expect(AppInfo.topVersion(ofChangelog: text) == "0.10.0")
        #expect(AppInfo.topVersion(ofChangelog: "## 메모\n") == nil)
        #expect(AppInfo.isNewer("0.10.0", than: "0.9.1"))
        #expect(!AppInfo.isNewer("0.2", than: "0.2.0"))
        #expect(AppInfo.topVersion(ofChangelog: AppInfo.changelog(lang: "ko")) != nil)
    }

    /// 번역 패치노트가 한국어 원본과 같은 버전 제목을 같은 순서로 갖는다
    @Test func changelogTranslationsMatchVersions() {
        func versions(_ text: String) -> [String] { text.split(separator: "\n").filter { $0.hasPrefix("## ") }.map(String.init) }
        let ko = versions(AppInfo.changelog(lang: "ko"))
        #expect(!ko.isEmpty)
        for lang in ["en", "ja"] { #expect(versions(AppInfo.changelog(lang: lang)) == ko, "\(lang)") }
    }
}
