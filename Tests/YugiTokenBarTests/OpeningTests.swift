import Foundation
import Testing
@testable import YugiTokenBar

@Suite struct OpeningTests {
    /// 개봉 화면의 [한 팩 더] 는 지금 연 팩을 알아야 하고, 무료 카드 개봉에는 팩이 없다.
    @MainActor @Test func openingPackFollowsSource() throws {
        let store = StateStore(url: tempDir().appendingPathComponent("state.json"))
        var state = GameState()
        state.coins = Balance.packPrice
        state.pendingFree = 1
        try store.save(state)
        let model = AppModel(db: makeDB([[(1, 1)], [(2, 1)]]), store: store)

        #expect(model.buy(pack: 1))
        #expect(model.openingPack == 1 && model.showOpening)
        #expect(model.openFree())
        #expect(model.openingPack == nil)
    }
}
