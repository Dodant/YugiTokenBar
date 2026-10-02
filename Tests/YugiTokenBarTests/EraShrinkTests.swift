import Testing
@testable import YugiTokenBar

@Suite struct EraShrinkTests {
    /// 시대 범위를 줄인 뒤 남은 옛 팩 인덱스로 사면 코인을 쓰지 않고 빈 결과.
    @Test func buyingPackOutsideRangeIsRefused() {
        var game = Game(db: makeDB([[(1, 1)], [(2, 1)]]), state: GameState())
        game.state.coins = Balance.packPrice
        var rng = SeededRNG(seed: 1)
        let pulls = game.buy(pack: 5, using: &rng)
        #expect(pulls.isEmpty)
        #expect(game.state.coins == Balance.packPrice)
    }
}
