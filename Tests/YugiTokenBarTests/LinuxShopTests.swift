#if os(Linux)
import Adwaita
import CAdw
import Foundation
import Testing
@testable import YugiTokenBar

/// Real GTK activation and redraw. Run scripts/test-linux-ui.sh under Xvfb.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["YTB_GTK_UI_TESTS"] == "1"))
@MainActor struct LinuxShopTests {
    func find(_ name: String, in widget: UnsafeMutablePointer<GtkWidget>) -> UnsafeMutablePointer<GtkWidget>? {
        if gtk_widget_get_mapped(widget) != 0, String(cString: gtk_widget_get_name(widget)) == name { return widget }
        var child = gtk_widget_get_first_child(widget)
        while let current = child {
            if let result = find(name, in: current) { return result }
            child = gtk_widget_get_next_sibling(current)
        }
        return nil
    }
    func pump() async {
        for _ in 0..<30 {
            while g_main_context_iteration(nil, 0) != 0 {}
            LinuxImageLoader.shared.drain()
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
    @Test func realShopSignalsAndReload() async throws {
        adw_init()
        let app = AdwaitaApp(id: "io.github.dodant.YugiTokenBar.ShopTest")
        let window = gtk_window_new()!
        g_object_ref_sink(UnsafeMutableRawPointer(window))
        defer { gtk_window_destroy(UnsafeMutableRawPointer(window).assumingMemoryBound(to: GtkWindow.self)); g_object_unref(UnsafeMutableRawPointer(window)) }
        gtk_window_set_default_size(UnsafeMutableRawPointer(window).assumingMemoryBound(to: GtkWindow.self), 1000, 680)
        let scene = SceneStorage(id: "shop-test", pointer: OpaquePointer(window), show: {})
        let data = WidgetData(sceneStorage: scene, appStorage: app)
        let root = tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StateStore(url: root.appendingPathComponent("state.json"))
        var state = GameState()
        state.coins = 5000; state.pendingFree = 9; state.freePacks = 1
        state.autoSellDuplicates = true
        // Five distinct draws guarantee one new card and four auto-sold duplicates.
        // A real passcode deliberately differs from each internal cid.
        var info = card("Blue-Eyes White Dragon")
        info = CardInfo(name: info.name, attr: nil, level: nil, type: nil, atk: nil, def: nil, text: "", imageId: 89631139)
        state.owned = [2: 1, 3: 1, 4: 1, 5: 1]
        let db = oneBoxDB(Dictionary(uniqueKeysWithValues: (1...5).map { ($0, info) }))
        let model = LinuxModel(game: Game(db: db, state: state), store: store)
        let storage = LinuxShellView(snapshot: model.snapshot, model: model).storage(data: data, type: AdwaitaMainView.self)
        LinuxShellView(snapshot: model.snapshot, model: model).updateStorage(storage, data: data, updateProperties: true, type: AdwaitaMainView.self)
        let content = try #require(storage.opaquePointer)
        gtk_window_set_child(UnsafeMutableRawPointer(window).assumingMemoryBound(to: GtkWindow.self), UnsafeMutablePointer<GtkWidget>(content))
        model.onPublish = { value in
            LinuxShellView(snapshot: value, model: model).updateStorage(storage, data: data, updateProperties: true, type: AdwaitaMainView.self)
        }
        gtk_window_present(UnsafeMutableRawPointer(window).assumingMemoryBound(to: GtkWindow.self))
        await pump()
        await screenshot("initial")
        func activate(_ id: String) throws {
            let widget = try #require(find(id, in: window))
            #expect(gtk_widget_is_sensitive(widget) != 0)
            #expect(gtk_widget_activate(widget) != 0)
        }
        try activate("shop-buy-0"); await pump()
        let opening = try #require(model.snapshot.opening)
        #expect(opening.pulls.count == 5)
        #expect(opening.pulls.filter(\.isNew).count == 1)
        #expect(opening.pulls.filter { $0.soldFor != nil }.count == 4)
        #expect(model.game.state.packStamp == 1)
        #expect(model.game.state.coins == state.coins - Balance.packPrice + opening.pulls.compactMap(\.soldFor).reduce(0, +))
        #expect(store.load() == model.game.state)
        #expect(find("shop-buy-0", in: window) == nil)
        let owned = model.game.state.owned
        #expect(!model.buy(pack: 0)); #expect(!model.openFree()); #expect(!model.openFreePack())
        #expect(model.game.state.owned == owned)
        if ProcessInfo.processInfo.environment["YTB_SMOKE_NO_IMAGES"] == "0" {
            for _ in 0..<30 {
                await pump()
                if FileManager.default.fileExists(atPath: ImageSource.cacheDirectory.appendingPathComponent("cards-89631139.jpg").path) { break }
            }
        }
        if ProcessInfo.processInfo.environment["YTB_SMOKE_NO_IMAGES"] == "0" {
            #expect(FileManager.default.fileExists(atPath: ImageSource.cacheDirectory.appendingPathComponent("cards-89631139.jpg").path))
        }
        await screenshot("paid-opening")
        try activate("sidebar-shop"); await pump() // Same selected Shop closes opening too.
        #expect(model.snapshot.opening == nil)
        let complete = try #require(find("shop-buy-0", in: window))
        #expect(gtk_widget_is_sensitive(complete) == 0) // Never force clicked on an insensitive button.
        try activate("shop-free-cards"); await pump()
        #expect(model.snapshot.opening?.pulls.count == Balance.freeOpenBatch)
        #expect(model.game.state.pendingFree == 9 - Balance.freeOpenBatch)
        #expect(model.game.state.packStamp == 1)
        try activate("opening-close"); await pump()
        try activate("shop-free-pack"); await pump()
        #expect(model.snapshot.opening?.freePack == true)
        #expect(model.snapshot.opening?.pulls.count == 5)
        #expect(model.game.state.freePacks == 0)
        #expect(model.game.state.packStamp == 1)
        #expect(store.load() == model.game.state)
        await screenshot("free-pack-opening")
        try activate("opening-close"); await pump()
        let emptyFreePack = try #require(find("shop-free-pack", in: window))
        #expect(gtk_widget_is_sensitive(emptyFreePack) == 0)
        await screenshot("shop-complete")
        model.onPublish = nil
        let poorStore = StateStore(url: root.appendingPathComponent("poor.json"))
        let poorModel = LinuxModel(game: Game(db: db, state: GameState()), store: poorStore)
        let poorView = LinuxShopView(snapshot: poorModel.snapshot, model: poorModel)
        let poorStorage = poorView.storage(data: data, type: AdwaitaMainView.self)
        poorView.updateStorage(poorStorage, data: data, updateProperties: true, type: AdwaitaMainView.self)
        gtk_window_set_child(UnsafeMutableRawPointer(window).assumingMemoryBound(to: GtkWindow.self), UnsafeMutablePointer<GtkWidget>(try #require(poorStorage.opaquePointer)))
        await pump()
        let poorBuy = try #require(find("shop-buy-0", in: window))
        #expect(gtk_widget_is_sensitive(poorBuy) == 0)
        #expect(!poorModel.buy(pack: 0)); #expect(!poorModel.openFree()); #expect(!poorModel.openFreePack())
        #expect(!FileManager.default.fileExists(atPath: poorStore.url.path))
        await screenshot("shop-insufficient")
        var fusion = card("Fusion result")
        fusion.picks = [Pick(any: [1], count: 2)]
        let fusionDB = oneBoxDB([1: card("Fusion material"), 2: fusion])
        var fusionState = GameState(); fusionState.coins = 5000; fusionState.fusionOnly = true
        fusionState.owned[1] = 2
        let fusionStore = StateStore(url: root.appendingPathComponent("fusion.json"))
        let fusionModel = LinuxModel(game: Game(db: fusionDB, state: fusionState), store: fusionStore)
        let fusionView = LinuxShopView(snapshot: fusionModel.snapshot, model: fusionModel)
        let fusionStorage = fusionView.storage(data: data, type: AdwaitaMainView.self)
        fusionView.updateStorage(fusionStorage, data: data, updateProperties: true, type: AdwaitaMainView.self)
        gtk_window_set_child(UnsafeMutableRawPointer(window).assumingMemoryBound(to: GtkWindow.self), UnsafeMutablePointer<GtkWidget>(try #require(fusionStorage.opaquePointer)))
        await pump()
        let fusionBuy = try #require(find("shop-buy-0", in: window))
        #expect(fusionModel.game.progress(0).cleared)
        #expect(!fusionModel.game.progress(0).complete)
        #expect(gtk_widget_is_sensitive(fusionBuy) == 0)
        #expect(!fusionModel.canBuy(pack: 0)); #expect(!fusionModel.buy(pack: 0))
        #expect(!FileManager.default.fileExists(atPath: fusionStore.url.path))
        await screenshot("shop-fusion-only")
        // The same cleared pack is useful while one more drawable material is needed.
        fusionState.owned[1] = 1
        let wantedModel = LinuxModel(game: Game(db: fusionDB, state: fusionState), store: fusionStore)
        let wantedView = LinuxShopView(snapshot: wantedModel.snapshot, model: wantedModel)
        let wantedStorage = wantedView.storage(data: data, type: AdwaitaMainView.self)
        wantedView.updateStorage(wantedStorage, data: data, updateProperties: true, type: AdwaitaMainView.self)
        gtk_window_set_child(UnsafeMutableRawPointer(window).assumingMemoryBound(to: GtkWindow.self), UnsafeMutablePointer<GtkWidget>(try #require(wantedStorage.opaquePointer)))
        await pump()
        #expect(wantedModel.game.progress(0).cleared)
        #expect(wantedModel.canBuy(pack: 0))
        await screenshot("shop-wanted-material")
        try activate("shop-buy-0"); await pump()
        #expect(wantedModel.game.state.coins == 4000)
        #expect(wantedModel.game.copies(1) == 2)
        #expect(wantedModel.game.copies(2) == 0)
        #expect(fusionStore.load() == wantedModel.game.state)
        print("SHOP_NATIVE_OK paid=1 freeCards=\(Balance.freeOpenBatch) freePacks=1 stamp=1 savedReload=true")
    }
    func screenshot(_ name: String) async {
        guard let path = ProcessInfo.processInfo.environment["YTB_GTK_UI_ARTIFACT_DIR"] else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/scrot")
        process.arguments = ["-o", "\(path)/\(name).png"]
        do { try process.run(); process.waitUntilExit(); #expect(process.terminationStatus == 0) }
        catch { Issue.record("Screenshot failed: \(error)") }
    }
}
#endif

#if os(Linux)
@Suite @MainActor struct LinuxOpeningPresentationTests {
    @Test func imageUsesPasscodeAndAcquisitionTimeOverframe() throws {
        let info = overframeCard("Overframe test")
        let db = oneBoxDB([1: info])
        var state = GameState(); state.overframes.insert(1)
        let game = Game(db: db, state: state)
        let beforeUnlock = Pull(cid: 1, tier: 1, isNew: true, overframe: false)
        let afterUnlock = Pull(cid: 1, tier: 1, isNew: false, overframe: true)
        let normal = try #require(LinuxOpeningView.imageRequest(for: beforeUnlock, game: game))
        let special = try #require(LinuxOpeningView.imageRequest(for: afterUnlock, game: game))
        let passcode = try #require(info.imageId)
        #expect(normal == ImageSource.card(imageID: passcode, size: .full, overframe: false))
        #expect(special == ImageSource.card(imageID: passcode, size: .full, overframe: true))
        #expect(normal.key != special.key)
    }
}
#endif
