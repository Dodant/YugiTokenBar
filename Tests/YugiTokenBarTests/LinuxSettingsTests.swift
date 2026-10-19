#if os(Linux)
import Adwaita
import CAdw
import Foundation
import Testing
@testable import YugiTokenBar

/// Real GTK activation of the backup & transfer controls. Run scripts/test-linux-ui.sh under Xvfb.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["YTB_GTK_UI_TESTS"] == "1"))
@MainActor struct LinuxSettingsTests {
    @Test func transferControlsConfirmationAndDirtyExport() async throws {
        adw_init()
        let app = AdwaitaApp(id: "io.github.dodant.YugiTokenBar.SettingsTest")
        let window = adw_window_new()!
        g_object_ref_sink(UnsafeMutableRawPointer(window))
        defer { gtk_window_destroy(UnsafeMutableRawPointer(window).assumingMemoryBound(to: GtkWindow.self)); g_object_unref(UnsafeMutableRawPointer(window)) }
        gtk_window_set_default_size(UnsafeMutableRawPointer(window).assumingMemoryBound(to: GtkWindow.self), 1000, 760)
        let scene = SceneStorage(id: "settings-test", pointer: OpaquePointer(window), show: {})
        let data = WidgetData(sceneStorage: scene, appStorage: app)
        let root = tempDir(), blocker = root.appendingPathComponent("save")
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: blocker) // a file where the save folder should be: every save fails until it is removed
        let store = StateStore(url: blocker.appendingPathComponent("state.json"))
        let service = LinuxUsageService(read: { _, _ in .init(date: "2026-10-19") }, history: { _ in [:] })
        var state = GameState(); state.coins = 50; state.owned = [1: 1]
        let model = LinuxModel(game: Game(db: oneBoxDB([1: card("A"), 2: card("B")]), state: state), store: store, service: service)
        let storage = LinuxShellView(snapshot: model.snapshot, model: model).storage(data: data, type: AdwaitaMainView.self)
        func redraw() { LinuxShellView(snapshot: model.snapshot, model: model).updateStorage(storage, data: data, updateProperties: true, type: AdwaitaMainView.self) }
        redraw()
        adw_window_set_content(UnsafeMutableRawPointer(window).assumingMemoryBound(to: AdwWindow.self), UnsafeMutablePointer<GtkWidget>(try #require(storage.opaquePointer)))
        model.onPublish = { _ in redraw() }
        gtk_window_present(UnsafeMutableRawPointer(window).assumingMemoryBound(to: GtkWindow.self))
        await LinuxGTK.pump(model)
        func sensitive(_ id: String) throws -> Bool { gtk_widget_is_sensitive(try #require(LinuxGTK.find(id, in: window))) != 0 }
        func activate(_ id: String) async throws {
            #expect(try sensitive(id))
            #expect(gtk_widget_activate(try #require(LinuxGTK.find(id, in: window))) != 0)
            await LinuxGTK.pump(model); redraw(); await LinuxGTK.pump(model)
        }
        func labels() -> [String] {
            var found: [String] = []
            func walk(_ w: LinuxGTK.Widget) {
                guard gtk_widget_get_mapped(w) != 0 else { return }
                if String(cString: gtk_widget_get_css_name(w)) == "label" { found.append(String(cString: gtk_label_get_text(OpaquePointer(w)))) }
                var child = gtk_widget_get_first_child(w)
                while let c = child { walk(c); child = gtk_widget_get_next_sibling(c) }
            }
            walk(window); return found
        }

        try await activate("sidebar-settings")
        #expect(try sensitive("settings-export")); #expect(try sensitive("settings-import"))
        // Not activated: a modal GtkFileDialog would block under Xvfb. The portal round trip is Task 13.
        #expect(LinuxGTK.find("dirty-export", in: window) == nil)
        model.setAutoSellDuplicates(true) // save fails, progress cannot be written
        await LinuxGTK.pump(model)
        #expect(model.snapshot.dirty); #expect(try sensitive("dirty-export"))
        await LinuxGTK.screenshot("dirty-export")
        try FileManager.default.removeItem(at: blocker)
        #expect(model.retrySave()); await LinuxGTK.pump(model)
        #expect(LinuxGTK.find("dirty-export", in: window) == nil)

        var incoming = GameState(); incoming.coins = 777; incoming.owned = [1: 1, 2: 4]
        let file = root.appendingPathComponent("incoming.json")
        try SaveEnvelope(appVersion: "9.9.9", exportedAt: Date(timeIntervalSince1970: 1_700_000_000), state: incoming).encoded().write(to: file)
        model.prepareImport(at: file)
        await LinuxGTK.pump(model)
        #expect(try sensitive("import-confirm")); #expect(try sensitive("import-cancel"))
        let fact = L("가져올 세이브: 카드 %lld종 · %@\n(%@, v%@)\n지금 세이브: 카드 %lld종 · %@\n\n지금 세이브는 세이브 폴더에 자동 백업돼요.",
                     .int(2), .text(coinText(777)), .text(stamp(Date(timeIntervalSince1970: 1_700_000_000), "yyyy-MM-dd HH:mm")),
                     .text("9.9.9"), .int(1), .text(coinText(50)))
        #expect(labels().contains(fact))
        await LinuxGTK.screenshot("import-confirm")
        try await activate("import-cancel")
        #expect(model.snapshot.pendingImport == nil); #expect(model.game.state.coins == 50)
        #expect(LinuxGTK.find("import-confirm", in: window) == nil)
        model.prepareImport(at: file); await LinuxGTK.pump(model)
        try await activate("import-confirm")
        #expect(model.game.state.coins == 777); #expect(model.game.copies(2) == 4)
        #expect(store.load() == model.game.state); #expect(LinuxGTK.find("import-confirm", in: window) == nil)
        let backups = try FileManager.default.contentsOfDirectory(atPath: blocker.path).filter { $0.hasPrefix("state.import-backup-") }
        #expect(backups.count == 1)
        #expect(labels().contains(L("이전 세이브는 %@로 백업했어요.", .text(backups[0]))))
        await LinuxGTK.screenshot("settings-transfer")
        print("SETTINGS_NATIVE_OK backups=\(backups.count)")
    }
}
#endif
