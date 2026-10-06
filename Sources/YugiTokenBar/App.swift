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
        // swift run 바이너리엔 Info.plist(LSUIElement)가 없어 창이 키보드 입력을 못 받는다 → .app 과 같은 정책을 직접 건다
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView().environmentObject(model).environment(\.animationsOff, model.game.state.animationsOff)
        } label: {
            MenuBarLabel(title: menuTitle, icon: model.partner.menu, unlocked: model.game.state.partnerUnlocked)
        }
        .menuBarExtraStyle(.window)

        Window("컬렉션", id: "dex") {
            DexView().environmentObject(model).environment(\.animationsOff, model.game.state.animationsOff)
        }
        .defaultSize(width: 980, height: 640)

        Window("패치노트", id: "changelog") { DocView(text: AppInfo.changelog) }
            .defaultSize(width: 520, height: 600)

        Window("라이선스", id: "license") { DocView(text: AppInfo.license) }
            .defaultSize(width: 620, height: 600)
    }

    private var menuTitle: String {
        let state = model.game.state
        let coins = shortCoins(state.coins)
        return state.pendingFree > 0 ? "\(coins) ·\(state.pendingFree)" : coins
    }
}

/// 메뉴바 라벨: 파트너가 해금되면 카드 아이콘 자리에 날개 크리보. 코인·배지 글자는 그대로.
private struct MenuBarLabel: View {
    let title: String
    @ObservedObject var icon: FrameBox
    let unlocked: Bool

    var body: some View {
        if unlocked, let image = icon.image {
            Label { Text(title) } icon: { Image(nsImage: image) }
                .labelStyle(.titleAndIcon)
        } else {
            Label(title, systemImage: "rectangle.portrait.on.rectangle.portrait.fill")
                .labelStyle(.titleAndIcon)
        }
    }
}
