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
        model.latestVersionFetcher = { nil } // no test may reach GitHub, even if the model is later started
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

    @Test func preferencesAndSupportControls() async throws {
        adw_init()
        let app = AdwaitaApp(id: "io.github.dodant.YugiTokenBar.PreferencesTest")
        let window = adw_window_new()!
        g_object_ref_sink(UnsafeMutableRawPointer(window))
        defer { gtk_window_destroy(UnsafeMutableRawPointer(window).assumingMemoryBound(to: GtkWindow.self)); g_object_unref(UnsafeMutableRawPointer(window)) }
        gtk_window_set_default_size(UnsafeMutableRawPointer(window).assumingMemoryBound(to: GtkWindow.self), 1000, 1000)
        let scene = SceneStorage(id: "preferences-test", pointer: OpaquePointer(window), show: {})
        let data = WidgetData(sceneStorage: scene, appStorage: app)
        let root = tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StateStore(url: root.appendingPathComponent("state.json"))
        let service = LinuxUsageService(read: { _, _ in .init(date: "2026-10-19") }, history: { _ in [:] })
        let model = LinuxModel(game: Game(db: makeDB((0..<12).map { [($0 + 1, 1)] }), state: GameState()), store: store, service: service)
        model.usageHistoryFile = nil
        model.scanRootsDebounce = .milliseconds(10)
        model.latestVersionFetcher = { "99.0.0" } // no test may reach GitHub
        var opened: [URL] = []
        model.opener = { opened.append($0); return nil }
        let scanKey = CustomScanRoots.defaultsKey(for: Provider.claude.rawValue)
        defer { UserDefaults.standard.removeObject(forKey: scanKey); AppLanguage.store(.system) }
        var restartRequests = 0
        func view() -> LinuxShellView { LinuxShellView(snapshot: model.snapshot, model: model, restart: { restartRequests += 1 }) }
        let storage = view().storage(data: data, type: AdwaitaMainView.self)
        func redraw() { view().updateStorage(storage, data: data, updateProperties: true, type: AdwaitaMainView.self) }
        redraw()
        adw_window_set_content(UnsafeMutableRawPointer(window).assumingMemoryBound(to: AdwWindow.self), UnsafeMutablePointer<GtkWidget>(try #require(storage.opaquePointer)))
        model.onPublish = { _ in redraw() }
        model.start()
        gtk_window_present(UnsafeMutableRawPointer(window).assumingMemoryBound(to: GtkWindow.self))
        await LinuxGTK.pump(model)
        func widget(_ id: String) throws -> LinuxGTK.Widget { try #require(LinuxGTK.find(id, in: window), "missing \(id)") }
        func settle() async { await LinuxGTK.pump(model); redraw(); await LinuxGTK.pump(model) }
        func activate(_ id: String) async throws {
            #expect(gtk_widget_is_sensitive(try widget(id)) != 0)
            #expect(gtk_widget_activate(try widget(id)) != 0)
            await settle()
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

        try await activate("sidebar-settings") // also starts the (fake) update check
        await settle()
        for id in ["settings-language", "settings-autosell", "settings-era", "settings-scan-provider", "settings-scan-roots",
                   "settings-changelog", "settings-repo", "settings-bug", "settings-license", "settings-export",
                   "settings-import", "settings-folder"] {
            #expect(gtk_widget_is_sensitive(try widget(id)) != 0, "\(id) not sensitive")
        }
        #expect(LinuxGTK.find("settings-restart", in: window) == nil)
        #expect(labels().contains(L("새 버전 v%@이 있어요", .text("99.0.0"))))
        await LinuxGTK.screenshot("settings")

        // Language: choosing another language stores it and offers the restart; picking the launch choice hides it again.
        let launch = AppLanguage.launchChoice
        let other = AppLanguage.allCases.firstIndex { $0 != launch }!
        gtk_drop_down_set_selected(OpaquePointer(try widget("settings-language")), guint(other)); await settle()
        #expect(AppLanguage.stored() == AppLanguage.allCases[other])
        try await activate("settings-restart") // the closure is injected, nothing is exec'd
        #expect(restartRequests == 1)
        gtk_drop_down_set_selected(OpaquePointer(try widget("settings-language")), guint(AppLanguage.allCases.firstIndex(of: launch)!)); await settle()
        #expect(LinuxGTK.find("settings-restart", in: window) == nil)

        // Game settings go through the model and the save.
        try await activate("settings-autosell")
        #expect(model.game.state.autoSellDuplicates); #expect(store.load().autoSellDuplicates)
        gtk_drop_down_set_selected(OpaquePointer(try widget("settings-era")), 0); await settle()
        #expect(model.game.state.eraLimit == "DM"); #expect(store.load().eraLimit == "DM")
        #expect(model.game.state.partnerUnlocked == false) // hidden fields stay as they were

        // Extra scan folders share the macOS defaults key and rebuild the reader.
        let generation = model.stateGeneration
        gtk_editable_set_text(OpaquePointer(try widget("settings-scan-roots")), "~/remote-logs/*/claude/projects"); await settle()
        #expect(CustomScanRoots.storedValue(for: Provider.claude.rawValue) == "~/remote-logs/*/claude/projects")
        await settle()
        #expect(model.stateGeneration == generation + 1)
        #expect(labels().contains(L("찾은 폴더: %lld", .int(0))))

        // Links go through the injected opener (the real one is GIO's default handler).
        try await activate("settings-repo"); try await activate("settings-bug"); try await activate("settings-folder")
        try await activate("settings-releases")
        #expect(opened.map(\.absoluteString).prefix(2) == [AppInfo.repoURL.absoluteString, AppInfo.bugReportURL.absoluteString])
        #expect(opened.last == AppInfo.releasesURL); #expect(opened.count == 4)

        // Scroll down so the support group is captured too.
        let scrolled = try #require(gtk_widget_get_ancestor(try widget("settings-license"), gtk_scrolled_window_get_type()))
        let adjustment = gtk_scrolled_window_get_vadjustment(OpaquePointer(scrolled))
        gtk_adjustment_set_value(adjustment, gtk_adjustment_get_upper(adjustment)); await settle()
        await LinuxGTK.screenshot("settings-info")
        try await activate("settings-changelog")
        // Rendered, not raw Markdown: the first `## ` heading and one `- ` item appear as their own labels.
        func expectRendered(_ text: String) {
            let lines = text.split(separator: "\n").map { String($0).replacingOccurrences(of: "**", with: "") }
            let heading = lines.first { $0.hasPrefix("## ") }.map { String($0.dropFirst(3)) } ?? lines.first ?? ""
            #expect(labels().contains(heading), "missing heading \(heading)")
            #expect(!labels().contains { $0.hasPrefix("#") || $0.contains("**") })
            if let item = lines.first(where: { $0.hasPrefix("- ") }) { #expect(labels().contains { $0.hasSuffix(String(item.dropFirst(2))) }) }
        }
        expectRendered(AppInfo.changelog)
        await LinuxGTK.screenshot("settings-changelog")

        // A failing handler is shown, not fatal.
        model.opener = { _ in "No application" }
        model.open(AppInfo.repoURL); await settle()
        #expect(labels().contains(L("열지 못했어요: %@", .text("No application"))))
        model.stop()
        print("SETTINGS_PREFERENCES_OK")
    }
}
#endif
