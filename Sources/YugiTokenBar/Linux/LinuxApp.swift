#if os(Linux)
import Adwaita
import Foundation

/// GTK owns UI publication; Swift worker tasks only enqueue Sendable events.
@main @MainActor struct LinuxApp: App {
    let app: AdwaitaApp
    let lifecycle: LinuxLifecycle
    @State private var snapshot: LinuxSnapshot?
    @State private var startupMessage = ""
    @State private var showStartup = false
    @State private var showQuitFailure = false

    init() {
        let app = AdwaitaApp(id: "io.github.dodant.YugiTokenBar")
        self.app = app
        let bootstrap = LinuxBootstrap.load()
        lifecycle = LinuxLifecycle(model: bootstrap.model, app: app)
        _snapshot = State(wrappedValue: bootstrap.model?.snapshot)
        // Meta optional State otherwise casts uninitialized storage to a valid nil value.
        _snapshot.rawValue = bootstrap.model?.snapshot
        _startupMessage = State(wrappedValue: bootstrap.message ?? "")
        _showStartup = State(wrappedValue: bootstrap.message != nil)
    }

    static func main() {
        let instance = setupApp()
        let value = instance._snapshot
        instance.lifecycle.model?.onPublish = { value.wrappedValue = $0 }
        let quitFailure = instance._showQuitFailure
        instance.lifecycle.onQuitFailure = { [weak lifecycle = instance.lifecycle] in
            // AlertDialog dismisses after the response callback. Reopen only afterward.
            let epoch = lifecycle?.model?.lifecycleEpoch
            Idle {
                guard let lifecycle, !lifecycle.finished,
                      lifecycle.model?.lifecycleEpoch == epoch else { return }
                quitFailure.wrappedValue = true
            }
        }
        instance.app.run {
            // GTK activate may repeat; reuse the single window and timer registration.
            instance.app.showWindow("main")
            instance.lifecycle.activate()
        }
        instance.lifecycle.stop()
        AppLog.writeAndFlush("Linux application exited normally")
        AppLog.flush()
    }

    var scene: Scene {
        Window(id: "main") { _ in
            VStack {
                if let snapshot, let model = lifecycle.model {
                    LinuxShellView(snapshot: snapshot, model: model)
                } else {
                    Text("YugiTokenBar").padding(30)
                }
            }
            .alertDialog(visible: $showStartup, heading: L("시작 알림"), body: startupMessage, id: "startup")
            .response(L("확인"), role: .default) {
                if lifecycle.model == nil { lifecycle.finishQuit() }
            }
            .alertDialog(visible: $showQuitFailure, heading: L("저장하지 못했어요"),
                         body: L("진행 상황을 저장하지 못했어요. 다시 시도하거나 변경을 버리고 종료할 수 있어요."), id: "quit")
            .response(L("취소"), role: .close) { }
            .response(L("다시 시도"), appearance: .suggested, role: .default) { _ = lifecycle.requestQuit() }
            .response(L("변경을 버리고 종료"), appearance: .destructive) { lifecycle.finishQuit() }
        }
        .defaultSize(width: 1000, height: 680)
        .minSize(width: 800, height: 560)
        .title("YugiTokenBar")
        .appKeyboardShortcut("q".ctrl()) { _ in _ = lifecycle.requestQuit() }
        .onClose { lifecycle.requestQuit() ? .close : .cancel }
    }
}

@MainActor struct LinuxBootstrap {
    var model: LinuxModel?
    var message: String?

    static func load(store: StateStore = .standard()) -> Self {
        do {
            let db = try CardDB.bundled()
            guard store.lock() else {
                return Self(message: L("같은 세이브를 사용하는 앱이 이미 실행 중이에요."))
            }
            if let schema = store.savedSchema(), schema > GameState.schemaVersion {
                return Self(message: L("더 새 버전 앱에서 만든 세이브예요. 앱을 업데이트한 뒤 다시 실행해 주세요."))
            }
            let loaded = store.loadReportingRecovery()
            let message: String?
            switch loaded.recovery {
            case .backup: message = L("세이브가 손상되어 백업에서 복구했어요. 손상된 파일은 따로 보관했어요.")
            case .fresh: message = L("세이브와 백업을 읽지 못해 새로 시작했어요. 손상된 파일은 따로 보관했어요.")
            case nil: message = nil
            }
            return Self(model: LinuxModel(game: Game(db: db, state: loaded.state), store: store), message: message)
        } catch {
            return Self(message: L("카드 데이터를 읽지 못했어요: %@", .text(error.localizedDescription)))
        }
    }
}

/// Each GLib source captures an immutable epoch so failed exec/restart cannot revive it.
@MainActor final class LinuxLifecycle {
    let model: LinuxModel?
    let app: AdwaitaApp
    var onQuitFailure: (() -> Void)?
    private var registeredEpoch: UInt64?
    private(set) var finished = false

    init(model: LinuxModel?, app: AdwaitaApp) { self.model = model; self.app = app }

    func activate() {
        guard !finished, let model else { return }
        model.start()
        let epoch = model.lifecycleEpoch
        guard registeredEpoch != epoch else { return }
        registeredEpoch = epoch
        Idle(delay: .milliseconds(100)) { [weak model] in
            guard let model, model.running, model.lifecycleEpoch == epoch else { return false }
            model.drainEvents()
            return true
        }
        Idle(delay: .seconds(60)) { [weak model] in
            guard let model, model.running, model.lifecycleEpoch == epoch else { return false }
            model.refresh()
            return true
        }
    }

    @discardableResult func requestQuit() -> Bool {
        guard !finished else { return true }
        if let model, !model.retrySave() { onQuitFailure?(); return false }
        finishQuit()
        return true
    }

    func stop() { model?.stop(); registeredEpoch = nil }

    func finishQuit() {
        guard !finished else { return }
        finished = true
        stop()
        AppLog.writeAndFlush("Linux application quitting")
        AppLog.flush()
        app.quit()
    }
}
#endif
