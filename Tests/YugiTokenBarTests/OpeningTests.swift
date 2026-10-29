#if os(macOS)
import Foundation
import Testing
@testable import YugiTokenBar

@Suite struct OpeningTests {
    /// 개봉 화면의 [한 팩 더] 는 지금 연 팩을 알아야 하고, 무료 카드 개봉에는 팩이 없다.
    @MainActor @Test func openingPackFollowsSource() throws {
        let (model, _) = try makeModel(makeDB([[(1, 1)], [(2, 1)]])) { $0.coins = Balance.packPrice; $0.pendingFree = 1 }

        #expect(model.buy(pack: 1))
        #expect(model.opening.pack == 1 && model.screen == .opening(back: .summary))
        #expect(model.openFree())
        #expect(model.opening.pack == nil)
    }

    /// 개봉은 연 화면 위에 뜨고, 한 팩 더를 해도 닫으면 처음 연 화면(상점)으로 돌아간다
    @MainActor @Test func openingReturnsToTheScreenItOpenedFrom() throws {
        let (model, _) = try makeModel(makeDB([[(1, 1)]])) { $0.coins = Balance.packPrice * 2 }
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
        let (model, _) = try makeModel(makeDB([[(1, 1)]])) { $0.coins = Balance.packPrice; $0.freePacks = 2 }

        #expect(model.openFreePack())
        #expect(model.opening.freePack && model.game.state.freePacks == 1)
        #expect(model.buy(pack: 0))
        #expect(!model.opening.freePack)
    }

    /// 무료 팩 [All] 은 남은 무료 팩을 다 연다
    @MainActor @Test func openAllFreePacksOpensEveryPack() throws {
        let (model, _) = try makeModel(makeDB([(1...10).map { ($0, 1) }])) { $0.freePacks = 3 }

        #expect(model.openAllFreePacks())
        #expect(model.game.state.freePacks == 0)
        #expect(model.opening.pulls.count == 15 && model.opening.freePack && model.opening.pack == nil)
        #expect(!model.openAllFreePacks())
    }
}
#endif
