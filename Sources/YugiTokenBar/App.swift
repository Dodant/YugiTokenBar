import SwiftUI

@main
struct YugiTokenBarApp: App {
    @State private var model: AppModel

    init() {
        _ = AppLanguage.launchChoice  // 실행할 때의 언어 선택을 고정 (설정에서 바꾸면 재시작 안내)
        // 끝난 codex 자식의 stdin 에 쓰면 SIGPIPE 가 앱을 죽인다 → 무시하고 EPIPE 로 받는다 (ProcessRunner)
        signal(SIGPIPE, SIG_IGN)
        let store = StateStore.standard()
        guard store.lock() else {
            Self.quit(String(localized: "YugiTokenBar가 이미 실행 중이에요"),
                      String(localized: "메뉴바에서 실행 중인 YugiTokenBar를 종료한 뒤 다시 열어 주세요."))
        }
        // 새 버전 앱이 쓴 세이브를 옛 버전이 저장하면 모르는 내용이 사라진다 → 열지 않는다
        if let schema = store.savedSchema(), schema > GameState.schemaVersion {
            Self.quit(String(localized: "더 새 버전 앱에서 쓴 세이브예요"),
                      String(localized: "세이브를 지키려고 이 버전은 열지 않아요. 최신 버전을 받아 열어 주세요."))
        }
        // ponytail: 카드 파일은 번들 리소스이고 CardDBTests 가 검증하므로 실패 시 화면 대신 명확한 메시지로 종료
        let db: CardDB
        do { db = try CardDB.bundled() } catch { fatalError("카드 파일 로드 실패: \(error)") }
        let model = AppModel(db: db, store: store)
        _model = State(initialValue: model)
        model.start()
        _ = Updater.controller  // Sparkle 자동 확인 일정 시작 (공개 키 없는 빌드는 nil)
        // swift run 바이너리엔 Info.plist(LSUIElement)가 없어 창이 키보드 입력을 못 받는다 → .app 과 같은 정책을 직접 건다
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    /// 알림을 띄우고 끝낸다 (모델을 만들기 전, 세이브를 건드리지 않고)
    private static func quit(_ title: String, _ message: String) -> Never {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.window.level = .floating  // 다른 앱을 쓰는 중이면 activate 가 거절돼 창이 뒤에 숨는다
        NSApplication.shared.activate()
        alert.runModal()
        exit(0)
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView().environment(model).environment(\.animationsOff, model.game.state.animationsOff)
                .environment(\.workMode, model.workMode)
        } label: {
            MenuBarLabel(title: menuTitle, icon: model.partner.menu, unlocked: model.game.state.partnerUnlocked && !model.workMode, saveFailed: model.saveError != nil)
        }
        .menuBarExtraStyle(.window)

        Window("컬렉션", id: "dex") {
            DexView().environment(model).environment(\.animationsOff, model.game.state.animationsOff)
                .environment(\.workMode, model.workMode)
        }
        .defaultSize(width: 980, height: 640)

        Window("패치노트", id: "changelog") { DocView(text: AppInfo.changelog) }
            .defaultSize(width: 520, height: 600)

        Window("License", id: "license") { DocView(text: AppInfo.license) }
            .defaultSize(width: 620, height: 600)
    }

    private var menuTitle: String {
        let state = model.game.state
        let coins = shortCoins(state.coins)
        return state.pendingFree > 0 ? "\(coins) · \(state.pendingFree)" : coins
    }
}

/// 메뉴바 라벨: 파트너가 해금되면 카드 아이콘 자리에 날개 크리보. 코인·배지 글자는 그대로.
private struct MenuBarLabel: View {
    let title: String
    let icon: FrameBox
    let unlocked: Bool
    /// 저장이 실패하면 아이콘 자리에 경고 (팝오버를 열지 않아도 보이게)
    let saveFailed: Bool

    var body: some View {
        if saveFailed {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .labelStyle(.titleAndIcon)
        } else if unlocked, let image = icon.image {
            Label { Text(title) } icon: { Image(nsImage: image) }
                .labelStyle(.titleAndIcon)
        } else {
            Label(title, systemImage: "rectangle.portrait.on.rectangle.portrait.fill")
                .labelStyle(.titleAndIcon)
        }
    }
}
