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
        #expect(model.openingPack == 1 && model.screen == .opening(back: .summary))
        #expect(model.openFree())
        #expect(model.openingPack == nil)
    }

    /// 개봉은 연 화면 위에 뜨고, 한 팩 더를 해도 닫으면 처음 연 화면(상점)으로 돌아간다
    @MainActor @Test func openingReturnsToTheScreenItOpenedFrom() throws {
        let store = StateStore(url: tempDir().appendingPathComponent("state.json"))
        var state = GameState()
        state.coins = Balance.packPrice * 2
        try store.save(state)
        let model = AppModel(db: makeDB([[(1, 1)]]), store: store, partner: PartnerModel(sheet: nil))
        model.screen = .shop
        #expect(model.buy(pack: 0))
        #expect(model.buy(pack: 0))  // 개봉 화면의 [한 팩 더]
        #expect(model.screen == .opening(back: .shop))
        model.closeOpening()
        #expect(model.screen == .shop)
        model.closeOpening()  // 개봉 화면이 아니면 그대로
        #expect(model.screen == .shop)
    }

    /// 무료 팩 개봉 화면은 무료 팩임을 알고(한 번 더가 다음 무료 팩), 코인으로 산 팩은 아니다
    @MainActor @Test func openingFreePackFollowsSource() throws {
        let store = StateStore(url: tempDir().appendingPathComponent("state.json"))
        var state = GameState()
        state.coins = Balance.packPrice
        state.freePacks = 2
        try store.save(state)
        let model = AppModel(db: makeDB([[(1, 1)]]), store: store, partner: PartnerModel(sheet: nil))

        #expect(model.openFreePack())
        #expect(model.openingFreePack && model.game.state.freePacks == 1)
        #expect(model.buy(pack: 0))
        #expect(!model.openingFreePack)
    }
}
