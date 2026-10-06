import Foundation
import Testing
@testable import YugiTokenBar

@Suite struct ClaimTests {
    let db = makeDB([[(1, 1), (2, 1)]])

    @Test func firstRunSeedsLedgerWithoutCredit() {
        var game = Game(db: db, state: GameState())
        var rng = SeededRNG(seed: 1)
        _ = game.claim(today: "2026-10-01", byProvider: ["claude_code": 50_000_000])
        #expect(game.state.coins == 0)
        #expect(game.state.dropProgress == 0)
        #expect(game.state.claimedByProvider == ["claude_code": 50_000_000])
    }

    @Test func sameTotalsTwiceCreditOnce() {
        var game = Game(db: db, state: GameState())
        var rng = SeededRNG(seed: 1)
        _ = game.claim(today: "2026-10-01", byProvider: ["claude_code": 0])
        _ = game.claim(today: "2026-10-01", byProvider: ["claude_code": 25_000, "codex": 5_000])
        _ = game.claim(today: "2026-10-01", byProvider: ["claude_code": 25_000, "codex": 5_000])
        #expect(game.state.coins == 3)
        #expect(game.state.dropProgress == 30_000)
    }

    @Test func transientLowReadingNeverDoubleCredits() {
        var game = Game(db: db, state: GameState())
        var rng = SeededRNG(seed: 1)
        _ = game.claim(today: "2026-10-01", byProvider: ["claude_code": 0])
        _ = game.claim(today: "2026-10-01", byProvider: ["claude_code": 100_000])
        _ = game.claim(today: "2026-10-01", byProvider: ["claude_code": 0])  // 로그 읽기 일시 실패
        _ = game.claim(today: "2026-10-01", byProvider: ["claude_code": 120_000])
        #expect(game.state.dropProgress == 120_000)
        #expect(game.state.claimedByProvider["claude_code"] == 120_000)
    }

    /// 날짜가 바뀌면 원장 날짜의 남은 몫과 앱이 꺼져 있던 날을 적립한다 (원장 날짜보다 앞은 버린다)
    @Test func newDayCreditsRestOfLedgerDayAndDaysAppWasOff() {
        var game = Game(db: db, state: GameState())
        _ = game.claim(today: "2026-10-01", byProvider: ["claude_code": 900_000])  // 첫 실행: 기준만
        _ = game.claim(today: "2026-10-01", byProvider: ["claude_code": 1_000_000])  // +100K
        _ = game.claim(today: "2026-10-04", byProvider: ["claude_code": 40_000], earlier: [
            "2026-09-30": ["claude_code": 999_999],
            "2026-10-01": ["claude_code": 1_200_000, "codex": 5_000],  // 꺼진 뒤 +200K, codex 는 원장에 없어서 전부
            "2026-10-02": ["claude_code": 300_000, "codex": 50_000],
        ])
        #expect(game.state.dropProgress == 100_000 + 205_000 + 350_000 + 40_000)
        #expect(game.state.claimedDate == "2026-10-04")
        #expect(game.state.claimedByProvider == ["claude_code": 40_000])
    }

    /// 첫 실행은 지난 날짜도 적립하지 않는다 (설치 전 사용량)
    @Test func firstRunIgnoresEarlierDays() {
        var game = Game(db: db, state: GameState())
        _ = game.claim(today: "2026-10-04", byProvider: ["claude_code": 40_000], earlier: ["2026-10-03": ["claude_code": 500_000]])
        #expect(game.state.dropProgress == 0)
    }

    @Test func newDayStartsLedgerFromZero() {
        var game = Game(db: db, state: GameState())
        var rng = SeededRNG(seed: 1)
        _ = game.claim(today: "2026-10-01", byProvider: ["claude_code": 900_000])
        _ = game.claim(today: "2026-10-04", byProvider: ["claude_code": 40_000])  // 며칠 꺼져 있다 켜짐
        #expect(game.state.dropProgress == 40_000)
        #expect(game.state.claimedDate == "2026-10-04")
    }

    @Test func coinsAndFreeCardsCarryRemainders() {
        var game = Game(db: db, state: GameState())
        var rng = SeededRNG(seed: 1)
        let got = game.credit(10_005_000)
        #expect(game.state.coins == 1_000)
        #expect(game.state.coinRemainder == 5_000)
        #expect(got == 1)
        #expect(game.state.dropProgress == 5_000)
        #expect(game.state.pendingFree == 1)
        #expect(game.state.owned.isEmpty)  // 직접 열기 전에는 뽑지 않는다
        _ = game.credit(5_000)
        #expect(game.state.coins == 1_001)
        #expect(game.state.coinRemainder == 0)
    }

    @Test func hugeCreditJustStacksFreeCards() {
        var game = Game(db: db, state: GameState())
        let got = game.credit(5_000_000_000)  // 무료 카드 500장분
        #expect(got == 500)
        #expect(game.state.pendingFree == 500)
        #expect(game.state.dropProgress == 0)
        #expect(game.state.coins == 500_000)
    }

    @Test func clockMovingBackwardsIsIgnored() {
        var game = Game(db: db, state: GameState())
        var rng = SeededRNG(seed: 1)
        _ = game.claim(today: "2026-10-02", byProvider: ["claude_code": 0])
        _ = game.claim(today: "2026-10-02", byProvider: ["claude_code": 25_000])
        let coins = game.state.coins
        _ = game.claim(today: "2026-10-01", byProvider: ["claude_code": 900_000])
        #expect(game.state.coins == coins)
        #expect(game.state.claimedDate == "2026-10-02")
    }

    @Test func openFreeDrawsPendingInBatches() {
        var game = Game(db: makeDB([(1...10).map { ($0, 1) }]), state: GameState())
        var rng = SeededRNG(seed: 1)
        game.credit(7 * Balance.tokensPerFreeCard)
        let first = game.openFree(using: &rng)
        #expect(first.count == Balance.freeOpenBatch)
        #expect(game.state.pendingFree == 2)
        #expect(game.openFree(using: &rng).count == 2)
        #expect(game.state.pendingFree == 0)
        #expect(game.openFree(using: &rng).isEmpty)
        #expect(game.state.owned.values.reduce(0, +) == 7)
        #expect(game.state.log.allSatisfy { $0.source == "free" })
    }

    @Test func openFreeHasNoCopyCap() {
        var game = Game(db: db, state: GameState())  // 2종뿐
        var rng = SeededRNG(seed: 1)
        game.credit(5 * Balance.tokensPerFreeCard)
        #expect(game.openFree(using: &rng).count == 5)
        #expect(game.state.owned.values.reduce(0, +) == 5)
    }
}

/// 매분 갱신: 늘어난 토큰이 없으면 저장하지 않고(파일을 다시 만들지 않음), 늘면 적립하고 저장한다
@MainActor @Test func modelClaimSavesOnlyWhenStateChanges() throws {
    let file = tempDir().appendingPathComponent("state.json")
    let model = AppModel(db: makeDB([[(1, 1)]]), store: StateStore(url: file), partner: PartnerModel(sheet: nil))
    model.claim(today: "2026-10-06", byProvider: ["claude_code": 100])
    #expect(FileManager.default.fileExists(atPath: file.path))
    try FileManager.default.removeItem(at: file)
    model.claim(today: "2026-10-06", byProvider: ["claude_code": 100])
    #expect(!FileManager.default.fileExists(atPath: file.path))
    model.claim(today: "2026-10-06", byProvider: ["claude_code": 100 + Balance.tokensPerCoin])
    #expect(FileManager.default.fileExists(atPath: file.path))
    #expect(model.game.state.coins == 1)
}

