import SwiftUI

@main
struct YugiTokenBarApp: App {
    @StateObject private var model: AppModel

    init() {
        // ponytail: cards.json 은 번들 리소스이고 CardDBTests 가 검증하므로 실패 시 화면 대신 명확한 메시지로 종료
        let db: CardDB
        do { db = try CardDB.bundled() } catch { fatalError("cards.json 로드 실패: \(error)") }
        let model = AppModel(db: db)
        _model = StateObject(wrappedValue: model)
        model.start()
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView().environmentObject(model)
        } label: {
            Text(menuTitle)
        }
        .menuBarExtraStyle(.window)
    }

    private var menuTitle: String {
        let state = model.game.state
        let coins = state.coins.formatted()
        return state.unseenFree > 0 ? "🃏 \(coins) ·\(state.unseenFree)" : "🃏 \(coins)"
    }
}
