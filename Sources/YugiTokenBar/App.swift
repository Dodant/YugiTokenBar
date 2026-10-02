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
            Label(menuTitle, systemImage: "rectangle.portrait.on.rectangle.portrait.fill")
                .labelStyle(.titleAndIcon)
        }
        .menuBarExtraStyle(.window)

        Window("컬렉션", id: "dex") {
            DexView().environmentObject(model)
        }
        .defaultSize(width: 980, height: 640)

        Window("패치노트", id: "changelog") { DocView(text: AppInfo.changelog) }
            .defaultSize(width: 520, height: 600)

        Window("라이선스", id: "license") { DocView(text: AppInfo.license) }
            .defaultSize(width: 620, height: 600)
    }

    private var menuTitle: String {
        let state = model.game.state
        let coins = state.coins.formatted()
        return state.pendingFree > 0 ? "\(coins) ·\(state.pendingFree)" : coins
    }
}
