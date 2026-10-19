#if os(Linux)
import Adwaita
import Foundation
import Glibc

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
            LinuxRestartSmoke.run(instance.lifecycle)
        }
        instance.lifecycle.stop()
        AppLog.writeAndFlush("Linux application exited normally")
        AppLog.flush()
    }

    var scene: Scene {
        Window(id: "main") { _ in
            VStack {
                if let snapshot, let model = lifecycle.model {
                    LinuxShellView(snapshot: snapshot, model: model, restart: { lifecycle.restart() })
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
    /// Registers a repeating GLib source (delay, work -> keep running). Tests replace it to inspect liveness.
    var scheduler: (Duration, @escaping () -> Bool) -> Void = { delay, work in Idle(delay: delay, closure: work) }

    init(model: LinuxModel?, app: AdwaitaApp) { self.model = model; self.app = app }

    var isRegistered: Bool { registeredEpoch != nil }

    func activate() {
        guard !finished, let model else { return }
        model.start()
        LinuxImageLoader.shared.resume()
        let epoch = model.lifecycleEpoch
        guard registeredEpoch != epoch else { return }
        registeredEpoch = epoch
        scheduler(.milliseconds(100)) { [weak model] in
            guard let model, model.running, model.lifecycleEpoch == epoch else { return false }
            model.drainEvents()
            LinuxImageLoader.shared.drain()
            return true
        }
        scheduler(.seconds(60)) { [weak model] in
            guard let model, model.running, model.lifecycleEpoch == epoch else { return false }
            model.refresh()
            return true
        }
    }

    /// The running executable, resolved through /proc so a PATH lookup or a moved argv[0] cannot change the target.
    nonisolated static func currentExecutable() -> String? {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX) + 1)
        let count = readlink("/proc/self/exe", &buffer, buffer.count - 1)
        return count > 0 ? String(decoding: buffer.prefix(count).map { UInt8(bitPattern: $0) }, as: UTF8.self) : nil
    }

    /// execv with the full argv and the inherited environment. Returns errno only when exec failed.
    nonisolated static func systemExec(_ path: String, _ args: [String]) -> Int32 {
        var argv: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) } + [nil]
        defer { for pointer in argv { free(pointer) } }
        _ = execv(path, &argv)
        return errno
    }

    /// Save, flush defaults, stop every worker, then replace this process image. If exec returns, resume with a
    /// fresh epoch: the stopped epoch's GLib sources return false on their next tick and stay dead.
    @discardableResult func restart(executable: String? = LinuxLifecycle.currentExecutable(),
                                    exec: (String, [String]) -> Int32 = LinuxLifecycle.systemExec) -> Bool {
        guard !finished, let model else { return false }
        model.recordRestartError(nil)
        guard model.retrySave() else { model.recordRestartError(L("저장하지 못했어요")); return false }
        guard UserDefaults.standard.synchronize() else { model.recordRestartError(L("저장하지 못했어요")); return false }
        guard let executable else {
            model.recordRestartError(L("다시 열지 못했어요: %@", .text("executable not found"))); return false
        }
        stop()
        AppLog.writeAndFlush("Restarting for language change")
        AppLog.flush()
        let code = exec(executable, CommandLine.arguments)
        // Only reached when exec failed. The state lock fd was never closed, so it is still held.
        activate()
        model.recordRestartError(L("다시 열지 못했어요: %@", .text(String(cString: strerror(code)))))
        return false
    }

    @discardableResult func requestQuit() -> Bool {
        guard !finished else { return true }
        if let model, !model.retrySave() { onQuitFailure?(); return false }
        finishQuit()
        return true
    }

    func stop() { model?.stop(); registeredEpoch = nil; LinuxImageLoader.shared.stop() }

    func finishQuit() {
        guard !finished else { return }
        finished = true
        stop()
        AppLog.writeAndFlush("Linux application quitting")
        AppLog.flush()
        app.quit()
    }
}

/// scripts/test-linux-restart.sh drives a real exec through the built binary. Inert unless YTB_SMOKE_RESTART=1.
@MainActor enum LinuxRestartSmoke {
    private static var started = false

    static func run(_ lifecycle: LinuxLifecycle) {
        let env = ProcessInfo.processInfo.environment
        guard env["YTB_SMOKE_RESTART"] == "1", !started else { return }
        started = true
        let override = env["YTB_SMOKE_RESTART_EXEC"]
        func say(_ line: String) { print(line); fflush(nil) }
        guard lifecycle.model != nil else { say("SMOKE_RESTART_NO_MODEL"); return } // e.g. the state lock was not re-acquired
        if env["YTB_SMOKE_RESTARTED"] == "1" {
            say("SMOKE_RESTART_OK language=\(AppLanguage.current) stored=\(AppLanguage.stored().rawValue)")
            // Linger so the script can inspect the live process before the normal quit.
            Idle(delay: .seconds(4)) { _ = lifecycle.requestQuit(); return false }
            return
        }
        AppLanguage.store(.ja)
        setenv("YTB_SMOKE_RESTARTED", "1", 1)
        Idle {
            let exec: (String, [String]) -> Int32 = override.map { target in
                { _, args in LinuxLifecycle.systemExec(target, args) }
            } ?? LinuxLifecycle.systemExec
            _ = lifecycle.restart(exec: exec)
            // Reached only when exec failed: try again once on the resumed epoch, then quit normally.
            say("SMOKE_RESTART_FAILED error=\(lifecycle.model?.snapshot.restartError ?? "-")")
            _ = lifecycle.restart(exec: exec)
            say("SMOKE_RESTART_FAILED_AGAIN epoch=\(lifecycle.model?.lifecycleEpoch ?? 0)")
            Idle(delay: .seconds(4)) { _ = lifecycle.requestQuit(); return false }
        }
    }
}
#endif
