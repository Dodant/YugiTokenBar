#if os(Linux)
import Adwaita
import CAdw
import Foundation
import Testing
@testable import YugiTokenBar

func usageSum(_ total: Int) -> TokenSum { var sum = TokenSum(); sum.input = total; return sum }

@Suite struct LinuxUsageRowsTests {
    @Test func ordersOldestFirstSumsProvidersAndExcludesToday() {
        let days: UsageByDay = [
            "2026-10-18": ["codex": usageSum(10), "claude_code": usageSum(5)],
            "2026-09-19": [:],
            "2026-10-01": ["grok": usageSum(40)],
            "2026-10-19": ["codex": usageSum(999)],
        ]
        let rows = LinuxUsageRows.history(days, excluding: "2026-10-19")
        #expect(rows.map(\.day) == ["2026-09-19", "2026-10-01", "2026-10-18"])
        #expect(rows.map(\.total) == [0, 40, 15])
        #expect(LinuxUsageRows.maxTotal(rows) == 40)
        #expect(LinuxUsageRows.barTotal(rows) == 40)
    }

    @Test func allZeroNeverDividesByZero() {
        let rows = LinuxUsageRows.history(["2026-10-01": [:], "2026-10-02": ["codex": usageSum(0)]])
        #expect(rows.count == 2); #expect(LinuxUsageRows.maxTotal(rows) == 0)
        #expect(LinuxUsageRows.barTotal(rows) == 1)
        #expect(Double(rows[0].total) / LinuxUsageRows.barTotal(rows) == 0)
        #expect(LinuxUsageRows.history([:]).isEmpty); #expect(LinuxUsageRows.barTotal([]) == 1)
    }
}

/// Real GTK activation of the usage screen. Run scripts/test-linux-ui.sh under Xvfb.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["YTB_GTK_UI_TESTS"] == "1"))
@MainActor struct LinuxUsageTests {
    private final class Flag: @unchecked Sendable { var fail = true }

    @Test func historyRowsBarsAndRetry() async throws {
        adw_init()
        let app = AdwaitaApp(id: "io.github.dodant.YugiTokenBar.UsageTest")
        let window = adw_window_new()!
        g_object_ref_sink(UnsafeMutableRawPointer(window))
        defer { gtk_window_destroy(UnsafeMutableRawPointer(window).assumingMemoryBound(to: GtkWindow.self)); g_object_unref(UnsafeMutableRawPointer(window)) }
        gtk_window_set_default_size(UnsafeMutableRawPointer(window).assumingMemoryBound(to: GtkWindow.self), 1000, 900)
        let scene = SceneStorage(id: "usage-test", pointer: OpaquePointer(window), show: {})
        let data = WidgetData(sceneStorage: scene, appStorage: app)
        let root = tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let formatter = LocalUsageReader.localDayFormatter()
        let today = formatter.string(from: Date())
        let days = (1...31).map { formatter.string(from: Date().addingTimeInterval(Double(-$0) * 86_400)) }
        var history: UsageByDay = [:]
        for day in days { history[day] = [:] }
        history[days[0]] = ["codex": usageSum(2_000_000), "claude_code": usageSum(500_000)] // yesterday, the maximum
        history[days[4]] = ["grok": usageSum(1_000_000)]
        history[days[30]] = ["pi": usageSum(250_000)]
        let fixed = history
        let flag = Flag()
        let service = LinuxUsageService(
            read: { _, _ in .init(date: today, byProvider: ["codex": 1_500], detail: ["codex": usageSum(1_500)]) },
            history: { _ in if flag.fail { throw CocoaError(.fileReadUnknown) }; return fixed })
        let store = StateStore(url: root.appendingPathComponent("state.json"))
        let model = LinuxModel(game: Game(db: oneBoxDB([1: card("A")]), state: GameState()), store: store, service: service)
        let storage = LinuxShellView(snapshot: model.snapshot, model: model).storage(data: data, type: AdwaitaMainView.self)
        func redraw() { LinuxShellView(snapshot: model.snapshot, model: model).updateStorage(storage, data: data, updateProperties: true, type: AdwaitaMainView.self) }
        redraw()
        adw_window_set_content(UnsafeMutableRawPointer(window).assumingMemoryBound(to: AdwWindow.self), UnsafeMutablePointer<GtkWidget>(storage.opaquePointer!))
        model.onPublish = { _ in redraw() }
        gtk_window_present(UnsafeMutableRawPointer(window).assumingMemoryBound(to: GtkWindow.self))
        model.start()
        await LinuxGTK.pump(model)
        func activate(_ id: String) async throws {
            let widget = try #require(LinuxGTK.find(id, in: window))
            #expect(gtk_widget_is_sensitive(widget) != 0)
            #expect(gtk_widget_activate(widget) != 0)
            await LinuxGTK.pump(model)
            redraw(); await LinuxGTK.pump(model) // @State (sidebar section) is redrawn by the app scene; this harness has none.
        }
        func labels(_ widget: LinuxGTK.Widget) -> [String] {
            var found: [String] = []
            func walk(_ w: LinuxGTK.Widget) {
                guard gtk_widget_get_mapped(w) != 0 else { return }
                if String(cString: gtk_widget_get_css_name(w)) == "label" { found.append(String(cString: gtk_label_get_text(OpaquePointer(w)))) }
                var child = gtk_widget_get_first_child(w)
                while let c = child { walk(c); child = gtk_widget_get_next_sibling(c) }
            }
            walk(widget); return found
        }

        // First entry requests history; the failing reader shows the error and a retry button.
        try await activate("sidebar-usage")
        #expect(model.snapshot.historyError != nil); #expect(model.snapshot.history == nil)
        #expect(LinuxGTK.find("usage-retry-history", in: window) != nil)
        await LinuxGTK.screenshot("usage-error")
        flag.fail = false
        try await activate("usage-retry-history")
        #expect(model.snapshot.historyError == nil); #expect(model.snapshot.historyDate == today)
        #expect(LinuxGTK.find("usage-retry-history", in: window) == nil)
        for day in days { #expect(LinuxGTK.find("usage-day-\(day)", in: window) != nil, "\(day)") }
        #expect(LinuxGTK.find("usage-day-\(today)", in: window) == nil)
        let yesterday = labels(try #require(LinuxGTK.find("usage-day-\(days[0])", in: window)))
        #expect(yesterday.contains(days[0])); #expect(yesterday.contains(shortTokens(2_500_000)))
        #expect(labels(try #require(LinuxGTK.find("usage-day-\(days[4])", in: window))).contains(shortTokens(1_000_000)))
        let shown = labels(window)
        #expect(shown.contains(model.snapshot.usageHeading())); #expect(shown.contains("Codex")); #expect(shown.contains("oh-my-pi"))
        await LinuxGTK.screenshot("usage")
        print("USAGE_NATIVE_OK rows=31 retry=true")
    }
}
#endif
