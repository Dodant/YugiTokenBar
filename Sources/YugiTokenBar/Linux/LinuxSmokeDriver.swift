#if os(Linux)
import Adwaita
import CAdw
import Foundation

/// End-to-end driver for scripts/linux-smoke.sh and scripts/linux-scenarios.sh.
/// Inert unless YTB_SMOKE_SCREEN (shop|dex|open|usage|setting) or YTB_SMOKE_SCENARIO (save-failure) is set.
/// It only activates the real GTK widgets by smoke name (mapped and sensitive), never calls view code,
/// and ends with the normal save-and-quit path. A missing widget or a timeout prints SMOKE_FAIL and exits 2.
@MainActor enum LinuxSmokeDriver {
    private(set) static var failed = false
    private static var started = false
    private typealias Widget = UnsafeMutablePointer<GtkWidget>
    private struct Step { var name: String; var run: () -> Bool }

    static func run(_ lifecycle: LinuxLifecycle) {
        let env = ProcessInfo.processInfo.environment
        let screen = env["YTB_SMOKE_SCREEN"], scenario = env["YTB_SMOKE_SCENARIO"]
        guard screen != nil || scenario != nil, !started, let model = lifecycle.model else { return }
        started = true
        let exitDelay = Int(env["YTB_SMOKE_EXIT_MS"] ?? "") ?? 1500
        let control = env["YTB_SMOKE_CONTROL"]
        func say(_ line: String) { print(line); fflush(nil) }
        func settled() -> Bool {
            model.running && !model.readInFlight && !model.snapshot.refreshing && model.snapshot.revision >= 1
        }
        func activate(_ id: String) -> Bool {
            guard let widget = find(id), gtk_widget_is_sensitive(widget) != 0 else { return false }
            return gtk_widget_activate(widget) != 0
        }
        func gate(_ file: String) -> Bool {
            control.map { FileManager.default.fileExists(atPath: "\($0)/\(file)") } ?? false
        }
        var ticks = 0
        func waitTicks(_ count: Int) -> Bool { ticks += 1; if ticks > count { ticks = 0; return true }; return false }

        var steps = [Step(name: "model settled", run: settled)]
        func act(_ id: String) { steps.append(Step(name: "activate \(id)", run: { activate(id) })) }
        func until(_ name: String, _ condition: @escaping () -> Bool) { steps.append(Step(name: name, run: condition)) }
        func ready(_ name: String) {
            until("settle") { waitTicks(3) }
            steps.append(Step(name: "ready", run: { say("SMOKE_READY screen=\(name) revision=\(model.snapshot.revision)"); return true }))
        }

        switch scenario ?? screen ?? "" {
        case "shop": ready("shop")
        case "dex":
            act("sidebar-dex"); act("dex-pack-0"); until("dex pack selected") { model.snapshot.dexPack == 0 }
            ready("dex")
        case "open":
            act("shop-buy-0"); until("opening shown") { model.snapshot.opening != nil }
            ready("open")
        case "usage":
            act("sidebar-usage")
            until("history loaded") { model.snapshot.history != nil && !model.snapshot.loadingHistory }
            ready("usage")
        case "setting":
            steps.append(Step(name: "no update fetch", run: { model.latestVersionFetcher = { nil }; return true }))
            act("sidebar-settings"); ready("setting")
        case "save-failure":
            ready("save-failure")
            until("state blocked") { gate("blocked") }
            act("shop-buy-0")
            until("dirty") { model.snapshot.dirty }
            until("dirty banner") { find("dirty-retry") != nil }
            steps.append(Step(name: "refused", run: {
                say("SMOKE_DIRTY")
                if lifecycle.requestQuit() { say("SMOKE_FAIL reason=quit was not refused while dirty"); return true }
                say("SMOKE_QUIT_REFUSED"); return true
            }))
            until("state unblocked") { gate("unblocked") }
            act("dirty-retry")
            until("saved again") { !model.snapshot.dirty }
            steps.append(Step(name: "retried", run: { say("SMOKE_RETRIED"); return true }))
        default:
            say("SMOKE_FAIL reason=unknown screen \(scenario ?? screen ?? "")"); failed = true; lifecycle.finishQuit(); return
        }

        var index = 0, stepTicks = 0
        Idle(delay: .milliseconds(50)) {
            guard !lifecycle.finished else { return false }
            if index >= steps.count {
                Idle(delay: .milliseconds(exitDelay)) { _ = lifecycle.requestQuit(); return false }
                return false
            }
            if steps[index].run() { index += 1; stepTicks = 0; return true }
            stepTicks += 1
            if stepTicks > 600 { // 30 s
                say("SMOKE_FAIL reason=timeout in step '\(steps[index].name)'")
                failed = true; lifecycle.finishQuit(); return false
            }
            return true
        }
    }

    private static func find(_ name: String) -> Widget? {
        guard let toplevels = gtk_window_get_toplevels() else { return nil }
        for i in 0..<g_list_model_get_n_items(toplevels) {
            guard let object = g_list_model_get_item(toplevels, i) else { continue }
            defer { g_object_unref(object) }
            if let found = find(name, in: object.assumingMemoryBound(to: GtkWidget.self)) { return found }
        }
        return nil
    }

    private static func find(_ name: String, in widget: Widget) -> Widget? {
        if gtk_widget_get_mapped(widget) != 0, String(cString: gtk_widget_get_name(widget)) == name { return widget }
        var child = gtk_widget_get_first_child(widget)
        while let current = child {
            if let found = find(name, in: current) { return found }
            child = gtk_widget_get_next_sibling(current)
        }
        return nil
    }
}
#endif
