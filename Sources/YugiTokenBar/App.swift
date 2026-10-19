#if os(macOS)
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
            MenuBarLabel(title: menuTitle, usage: menuUsage, icon: model.partner.menu,
                         unlocked: model.game.state.partnerUnlocked && !model.workMode, saveFailed: model.saveError != nil)
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

    /// 설정에서 고른 숫자. 열지 않은 무료 카드 배지는 코인에만 붙는다. 에이전트별 값은 색이 있어 `menuUsage`로 따로 그린다
    private var menuTitle: String {
        let state = model.game.state
        switch model.menuBarInfo {
        case .coins:
            let coins = shortCoins(state.coins)
            return state.pendingFree > 0 ? "\(coins) · \(state.pendingFree)" : coins
        case .todayUsage:
            // 메뉴바 칸을 아끼려고 소수점 없이
            let today = model.todayDetail.values, tokens = Double(today.map(\.total).reduce(0, +))
            let short = tokens >= 1e6 ? String(format: "%.0fM", tokens / 1e6) : tokens >= 1e3 ? String(format: "%.0fK", tokens / 1e3) : String(Int(tokens))
            return "\(short) · \(String(format: "$%.0f", today.map(\.cost).reduce(0, +)))"
        case .collection: return "\(model.game.ownedDistinct)/\(model.game.db.allCIDs.count)"
        case .sessionUsage, .weeklyUsage, .sessionWeeklyUsage, .sessionReset, .none: return ""
        }
    }

    /// 공식 한도를 읽은 에이전트(Claude·Codex)의 세션(5시간)·주간 %나 세션 남은 시간과 색 (사용량 칸과 같은 색)
    private var menuUsage: [(text: String, tint: Color)] {
        UsageView.agents.compactMap { a in
            let session = model.limitPercent(for: a.id, weekly: false).map { Int($0.rounded()) }
            let weekly = model.limitPercent(for: a.id, weekly: true).map { Int($0.rounded()) }
            let text: String? = switch model.menuBarInfo {
            case .sessionUsage: session.map { "\($0)%" }
            case .weeklyUsage: weekly.map { "\($0)%" }
            case .sessionWeeklyUsage: session == nil && weekly == nil ? nil : "\(session.map(String.init) ?? "–")/\(weekly.map(String.init) ?? "–")%"
            case .sessionReset: model.limitReset(for: a.id).map { Self.shortReset($0, now: model.clock) }
            default: nil
            }
            return text.map { ($0, a.tint) }
        }
    }

    /// "2d 3h", "1h 23m", "48m" (사용량 문구라 모든 언어에서 영어)
    static func shortReset(_ date: Date, now: Date) -> String {
        let mins = max(0, Int(date.timeIntervalSince(now) / 60))
        let h = mins / 60, m = mins % 60
        return h >= 24 ? "\(h / 24)d \(h % 24)h" : h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}

/// 메뉴바 라벨: 파트너가 해금되면 카드 아이콘 자리에 날개 크리보. 코인·배지 글자는 그대로.
private struct MenuBarLabel: View {
    let title: String
    /// 에이전트별 글자와 색 (비면 안 그림)
    let usage: [(text: String, tint: Color)]
    let icon: FrameBox
    let unlocked: Bool
    /// 저장이 실패하면 아이콘 자리에 경고 (팝오버를 열지 않아도 보이게)
    let saveFailed: Bool
    /// 메뉴바 글자색이 따르는 외관. 컬러 이미지 안 아이콘이 메뉴바 글자와 같은 색이 되게 넘긴다
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if !usage.isEmpty, let image = usageImage {
            Image(nsImage: image)
        } else {
            Label { Text(verbatim: title) } icon: { iconImage }
                .labelStyle(.titleAndIcon)
        }
    }

    private var iconImage: Image {
        if saveFailed { Image(systemName: "exclamationmark.triangle.fill") }
        else if unlocked, let image = icon.image { Image(nsImage: image) }
        else { Image(systemName: "rectangle.portrait.on.rectangle.portrait.fill") }
    }

    /// 메뉴바 라벨은 이미지 하나·글자 하나만 그리고 글자 색을 버린다 → 아이콘과 %를 한 컬러 이미지로 그린다
    private var usageImage: NSImage? {
        let renderer = ImageRenderer(content: HStack(spacing: 5) {
            iconImage
            HStack(spacing: 3) {
                ForEach(Array(usage.enumerated()), id: \.offset) { i, u in
                    if i > 0 { Text(verbatim: "·").foregroundStyle(.secondary) }
                    Text(verbatim: u.text).foregroundStyle(u.tint)
                }
            }
        }
        .font(Font(NSFont.menuBarFont(ofSize: 0)))
        .monospacedDigit()
        .environment(\.colorScheme, colorScheme))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        return renderer.nsImage
    }
}
#endif
