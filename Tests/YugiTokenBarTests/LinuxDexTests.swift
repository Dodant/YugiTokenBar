#if os(Linux)
import Adwaita
import CAdw
import Foundation
import Testing
@testable import YugiTokenBar

/// Real GTK activation of the collection screens. Run scripts/test-linux-ui.sh under Xvfb.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["YTB_GTK_UI_TESTS"] == "1"))
@MainActor struct LinuxDexTests {
    typealias Widget = UnsafeMutablePointer<GtkWidget>

    func find(_ name: String, in widget: Widget) -> Widget? {
        if gtk_widget_get_mapped(widget) != 0, String(cString: gtk_widget_get_name(widget)) == name { return widget }
        var child = gtk_widget_get_first_child(widget)
        while let current = child {
            if let result = find(name, in: current) { return result }
            child = gtk_widget_get_next_sibling(current)
        }
        return nil
    }
    /// Mapped label texts and picture CSS state below a widget.
    func walk(_ widget: Widget, labels: inout [String], pictures: inout [Bool]) {
        guard gtk_widget_get_mapped(widget) != 0 else { return }
        switch String(cString: gtk_widget_get_css_name(widget)) {
        case "label": labels.append(String(cString: gtk_label_get_text(OpaquePointer(widget))))
        case "picture": pictures.append(gtk_widget_has_css_class(widget, "dim-label") != 0)
        default: break
        }
        var child = gtk_widget_get_first_child(widget)
        while let current = child { walk(current, labels: &labels, pictures: &pictures); child = gtk_widget_get_next_sibling(current) }
    }
    func labels(in widget: Widget) -> [String] { var l: [String] = []; var p: [Bool] = []; walk(widget, labels: &l, pictures: &p); return l }
    func pump() async {
        for _ in 0..<30 {
            while g_main_context_iteration(nil, 0) != 0 {}
            LinuxImageLoader.shared.drain()
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
    func screenshot(_ name: String) async {
        guard let path = ProcessInfo.processInfo.environment["YTB_GTK_UI_ARTIFACT_DIR"] else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/scrot")
        process.arguments = ["-o", "\(path)/\(name).png"]
        do { try process.run(); process.waitUntilExit(); #expect(process.terminationStatus == 0) }
        catch { Issue.record("Screenshot failed: \(error)") }
    }

    @Test func collectionNavigationDetailAndSales() async throws {
        adw_init()
        let app = AdwaitaApp(id: "io.github.dodant.YugiTokenBar.DexTest")
        let window = adw_window_new()!
        g_object_ref_sink(UnsafeMutableRawPointer(window))
        defer { gtk_window_destroy(UnsafeMutableRawPointer(window).assumingMemoryBound(to: GtkWindow.self)); g_object_unref(UnsafeMutableRawPointer(window)) }
        gtk_window_set_default_size(UnsafeMutableRawPointer(window).assumingMemoryBound(to: GtkWindow.self), 1000, 760)
        let scene = SceneStorage(id: "dex-test", pointer: OpaquePointer(window), show: {})
        let data = WidgetData(sceneStorage: scene, appStorage: app)
        let root = tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StateStore(url: root.appendingPathComponent("state.json"))
        // Cards 1 and 4 have duplicates, 2 is a single copy, 3 is unowned.
        let dragon = CardInfo(name: "Test Dragon", attr: "어둠", level: 8, type: "드래곤족/일반", atk: "3000", def: "2500",
                              text: "Dex detail flavor text.", imageId: 89631139, tier: 2)
        var cards: [Int: CardInfo] = [1: dragon, 2: card("Single"), 3: card("Missing"), 4: card("Spare", tier: 3)]
        cards[4] = CardInfo(name: "Spare", attr: nil, level: nil, type: nil, atk: nil, def: nil, text: "", imageId: 46986414, tier: 3)
        var state = GameState()
        state.owned = [1: 3, 2: 1, 4: 4]
        let model = LinuxModel(game: Game(db: oneBoxDB(cards), state: state), store: store)
        let storage = LinuxShellView(snapshot: model.snapshot, model: model).storage(data: data, type: AdwaitaMainView.self)
        LinuxShellView(snapshot: model.snapshot, model: model).updateStorage(storage, data: data, updateProperties: true, type: AdwaitaMainView.self)
        adw_window_set_content(UnsafeMutableRawPointer(window).assumingMemoryBound(to: AdwWindow.self), UnsafeMutablePointer<GtkWidget>(try #require(storage.opaquePointer)))
        model.onPublish = { value in
            LinuxShellView(snapshot: value, model: model).updateStorage(storage, data: data, updateProperties: true, type: AdwaitaMainView.self)
        }
        gtk_window_present(UnsafeMutableRawPointer(window).assumingMemoryBound(to: GtkWindow.self))
        await pump()
        let top = window
        func activate(_ id: String) async throws {
            let widget = try #require(find(id, in: top))
            #expect(gtk_widget_is_sensitive(widget) != 0)
            #expect(gtk_widget_activate(widget) != 0)
            await pump() // GtkButton emits clicked from a timeout after activate.
            // View @State (sidebar section, bulk-sale confirmation) is redrawn by the app's scene; this harness has none.
            LinuxShellView(snapshot: model.snapshot, model: model).updateStorage(storage, data: data, updateProperties: true, type: AdwaitaMainView.self)
        }
        func sensitive(_ id: String) throws -> Bool { gtk_widget_is_sensitive(try #require(find(id, in: top))) != 0 }

        try await activate("sidebar-dex"); await pump()
        #expect(find("dex-pack-0", in: top) != nil)
        #expect(try sensitive("dex-sell-duplicates"))
        #expect(find("dex-back", in: top) == nil)
        await screenshot("dex-packs")

        try await activate("dex-pack-0"); await pump()
        #expect(model.snapshot.dexPack == 0)
        #expect(find("dex-back", in: top) != nil)
        for cid in 1...4 { #expect(find("dex-card-\(cid)", in: top) != nil) }
        func pictureDimmed(_ cid: Int) throws -> Bool {
            var l: [String] = []; var p: [Bool] = []
            walk(try #require(find("dex-card-\(cid)", in: top)), labels: &l, pictures: &p)
            #expect(p.count == 1)
            return p.first ?? false
        }
        #expect(try !pictureDimmed(1)); #expect(try pictureDimmed(3)) // unowned cell shows the dimmed card back
        let cell3 = labels(in: try #require(find("dex-card-3", in: top)))
        #expect(cell3.contains("Missing"))
        #expect(labels(in: try #require(find("dex-card-1", in: top))).contains(L("보유 %lld장", .int(3))))
        #expect(!labels(in: try #require(find("dex-card-2", in: top))).contains(L("보유 %lld장", .int(1))))
        await screenshot("dex-grid")

        try await activate("dex-card-1"); await pump()
        #expect(model.snapshot.dexCard == 1)
        var shown = labels(in: top)
        #expect(shown.contains("Test Dragon")); #expect(shown.contains(dragon.summary)); #expect(shown.contains("ATK 3000 / DEF 2500"))
        #expect(shown.contains("Dex detail flavor text.")); #expect(shown.contains(L("보유 %lld장", .int(3))))
        await screenshot("dex-detail")
        let price = model.game.sellPrice(1)
        let coins = model.game.state.coins
        try await activate("dex-sell-one"); await pump()
        #expect(model.game.copies(1) == 2); #expect(model.game.state.coins == coins + price)
        #expect(store.load() == model.game.state)
        shown = labels(in: top)
        #expect(shown.contains(L("보유 %lld장", .int(2))))
        try await activate("dex-sell-one"); await pump()
        #expect(model.game.copies(1) == 1); #expect(model.game.state.coins == coins + 2 * price)
        #expect(try !sensitive("dex-sell-one")) // the last copy is kept
        let kept = model.game.state
        #expect(!model.sell(1)); #expect(model.game.state == kept)
        model.selectDexCard(nil); await pump()
        #expect(find("dex-sell-one", in: top) == nil)
        try await activate("dex-back"); await pump()
        #expect(model.snapshot.dexPack == nil); #expect(find("dex-pack-0", in: top) != nil)

        let before = model.game.state.coins
        let value = model.game.duplicatesValue
        #expect(value.count == 3)
        try await activate("dex-sell-duplicates"); await pump()
        #expect(labels(in: top).contains(L("중복 카드 %lld장을 +%@에 팔까요?", .int(value.count), .text(coinText(value.coins)))))
        try await activate("dex-sell-duplicates-cancel"); await pump()
        #expect(model.game.state.coins == before); #expect(model.game.copies(4) == 4)
        #expect(find("dex-sell-duplicates-confirm", in: top) == nil)
        try await activate("dex-sell-duplicates"); await pump()
        try await activate("dex-sell-duplicates-confirm"); await pump()
        #expect(model.game.state.coins == before + value.coins)
        #expect(model.game.copies(4) == 1); #expect(model.game.copies(1) == 1); #expect(model.game.copies(2) == 1)
        #expect(store.load() == model.game.state)
        #expect(find("dex-sell-duplicates-confirm", in: top) == nil)
        #expect(try !sensitive("dex-sell-duplicates"))
        print("DEX_NATIVE_OK sold=\(value.count) coins=\(value.coins)")
    }
}
#endif
