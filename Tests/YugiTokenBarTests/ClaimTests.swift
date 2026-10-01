import Testing
@testable import YugiTokenBar

@Suite struct ClaimTests {
    let db = makeDB([[(1, 1), (2, 1)]])

    @Test func firstRunSeedsLedgerWithoutCredit() {
        var game = Game(db: db, state: GameState())
        var rng = SeededRNG(seed: 1)
        _ = game.claim(today: "2026-10-01", byProvider: ["claude_code": 50_000_000], using: &rng)
        #expect(game.state.coins == 0)
        #expect(game.state.dropProgress == 0)
        #expect(game.state.claimedByProvider == ["claude_code": 50_000_000])
    }

    @Test func sameTotalsTwiceCreditOnce() {
        var game = Game(db: db, state: GameState())
        var rng = SeededRNG(seed: 1)
        _ = game.claim(today: "2026-10-01", byProvider: ["claude_code": 0], using: &rng)
        _ = game.claim(today: "2026-10-01", byProvider: ["claude_code": 25_000, "codex": 5_000], using: &rng)
        _ = game.claim(today: "2026-10-01", byProvider: ["claude_code": 25_000, "codex": 5_000], using: &rng)
        #expect(game.state.coins == 3)
        #expect(game.state.dropProgress == 30_000)
    }

    @Test func transientLowReadingNeverDoubleCredits() {
        var game = Game(db: db, state: GameState())
        var rng = SeededRNG(seed: 1)
        _ = game.claim(today: "2026-10-01", byProvider: ["claude_code": 0], using: &rng)
        _ = game.claim(today: "2026-10-01", byProvider: ["claude_code": 100_000], using: &rng)
        _ = game.claim(today: "2026-10-01", byProvider: ["claude_code": 0], using: &rng)  // 로그 읽기 일시 실패
        _ = game.claim(today: "2026-10-01", byProvider: ["claude_code": 120_000], using: &rng)
        #expect(game.state.dropProgress == 120_000)
        #expect(game.state.claimedByProvider["claude_code"] == 120_000)
    }

    @Test func newDayStartsLedgerFromZero() {
        var game = Game(db: db, state: GameState())
        var rng = SeededRNG(seed: 1)
        _ = game.claim(today: "2026-10-01", byProvider: ["claude_code": 900_000], using: &rng)
        _ = game.claim(today: "2026-10-04", byProvider: ["claude_code": 40_000], using: &rng)  // 며칠 꺼져 있다 켜짐
        #expect(game.state.dropProgress == 40_000)
        #expect(game.state.claimedDate == "2026-10-04")
    }

    @Test func coinsAndFreeCardsCarryRemainders() {
        var game = Game(db: db, state: GameState())
        var rng = SeededRNG(seed: 1)
        let got = game.credit(10_005_000, using: &rng)
        #expect(game.state.coins == 1_000)
        #expect(game.state.coinRemainder == 5_000)
        #expect(got.count == 1)
        #expect(game.state.dropProgress == 5_000)
        #expect(game.state.unseenFree == 1)
        _ = game.credit(5_000, using: &rng)
        #expect(game.state.coins == 1_001)
        #expect(game.state.coinRemainder == 0)
    }

    @Test func hugeCreditWithFullCollectionDoesNotHang() {
        var state = GameState()
        state.owned = [1: 2, 2: 2]
        var game = Game(db: db, state: state)
        var rng = SeededRNG(seed: 1)
        let got = game.credit(5_000_000_000, using: &rng)  // 무료 카드 500장분
        #expect(got.isEmpty)
        #expect(game.state.dropProgress == 0)
        #expect(game.state.coins == 500_000)
    }
}
