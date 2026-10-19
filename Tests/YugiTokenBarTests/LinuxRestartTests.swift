#if os(Linux)
import Adwaita
import Foundation
import Testing
@testable import YugiTokenBar

@MainActor private func makeModel(store: StateStore, fetcher: (@Sendable () async -> String?)? = nil) -> LinuxModel {
    let service = LinuxUsageService(read: { _, _ in .init(date: "2026-10-19") }, history: { _ in [:] })
    var state = GameState(); state.coins = 7
    let model = LinuxModel(game: Game(db: makeDB([[(1, 1)]]), state: state), store: store, service: service)
    model.usageHistoryFile = nil
    if let fetcher { model.latestVersionFetcher = fetcher }
    return model
}

@Suite @MainActor struct LinuxRestartTests {
    @Test func failedExecKeepsLockStateAndASingleLiveTimerPair() throws {
        let dir = tempDir(), url = dir.appendingPathComponent("state.json")
        let store = StateStore(url: url)
        #expect(store.lock())
        try store.save(GameState())
        let before = try Data(contentsOf: url)
        let model = makeModel(store: store)
        let lifecycle = LinuxLifecycle(model: model, app: AdwaitaApp(id: "io.github.dodant.YugiTokenBar.RestartTest"))
        var sources: [(epoch: UInt64, delay: Duration, work: () -> Bool)] = []
        lifecycle.scheduler = { delay, work in sources.append((model.lifecycleEpoch, delay, work)) }
        lifecycle.activate()
        #expect(sources.count == 2)
        var execCalls = 0
        let failing: (String, [String]) -> Int32 = { path, args in
            execCalls += 1
            #expect(path == LinuxLifecycle.currentExecutable()); #expect(args == CommandLine.arguments)
            return ENOENT
        }
        for round in 1...2 {
            #expect(!lifecycle.restart(exec: failing))
            #expect(execCalls == round)
            #expect(model.running); #expect(lifecycle.isRegistered)
            #expect(model.snapshot.restartError == L("다시 열지 못했어요: %@", .text(String(cString: strerror(ENOENT)))))
            #expect(!StateStore(url: url).lock()) // this process still holds the lock
            #expect(try Data(contentsOf: url) == before)
        }
        #expect(model.lifecycleEpoch == 5) // start, then stop + start for each failed restart
        #expect(sources.count == 6)
        // Exactly one drain (100 ms) and one refresh (60 s) source per epoch; only the newest pair stays alive.
        let live = sources.filter { $0.work() }
        #expect(live.map(\.epoch) == [model.lifecycleEpoch, model.lifecycleEpoch])
        #expect(Set(live.map { $0.delay }) == [.milliseconds(100), .seconds(60)])
        #expect(Dictionary(grouping: sources, by: \.epoch).values.allSatisfy { $0.count == 2 })
        lifecycle.stop()
        #expect(sources.allSatisfy { !$0.work() })
    }

    @Test func unsavedProgressBlocksExec() throws {
        let dir = tempDir(), blocker = dir.appendingPathComponent("save")
        try Data().write(to: blocker)
        let model = makeModel(store: StateStore(url: blocker.appendingPathComponent("state.json")))
        let lifecycle = LinuxLifecycle(model: model, app: AdwaitaApp(id: "io.github.dodant.YugiTokenBar.RestartTest2"))
        lifecycle.scheduler = { _, _ in }
        lifecycle.activate()
        model.setAutoSellDuplicates(true)
        #expect(model.snapshot.dirty)
        var called = false
        #expect(!lifecycle.restart(exec: { _, _ in called = true; return 0 }))
        #expect(!called); #expect(model.running)
        #expect(model.snapshot.restartError == L("저장하지 못했어요"))
        lifecycle.stop()
    }

    @Test func updateCheckRunsOncePerLaunchAndRetriesFailures() async {
        actor Counter { var n = 0; var answers: [String?] = ["0.1.0"]; func next() -> String? { n += 1; return answers.isEmpty ? nil : answers.removeFirst() } }
        let counter = Counter()
        let model = makeModel(store: StateStore(url: tempDir().appendingPathComponent("state.json")),
                              fetcher: { await counter.next() })
        model.start()
        model.checkForUpdate(); model.checkForUpdate() // second call joins the in-flight one
        for _ in 0..<500 where model.snapshot.latestVersion == nil { model.drainEvents(); try? await Task.sleep(for: .milliseconds(5)) }
        #expect(model.snapshot.latestVersion == "0.1.0")
        model.checkForUpdate(); model.checkForUpdate()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await counter.n == 1) // a successful check is not repeated during this launch
        model.stop()
    }

    @Test func failedUpdateCheckMayBeRetried() async {
        actor Counter { var n = 0; func bump() -> Int { n += 1; return n } }
        let counter = Counter()
        let model = makeModel(store: StateStore(url: tempDir().appendingPathComponent("state.json")),
                              fetcher: { await counter.bump() == 1 ? nil : "9.9.9" })
        model.start()
        model.checkForUpdate()
        for _ in 0..<500 where await counter.n < 1 { try? await Task.sleep(for: .milliseconds(5)) }
        for _ in 0..<20 { model.drainEvents(); try? await Task.sleep(for: .milliseconds(5)) }
        #expect(model.snapshot.latestVersion == nil)
        model.checkForUpdate()
        for _ in 0..<500 where model.snapshot.latestVersion == nil { model.drainEvents(); try? await Task.sleep(for: .milliseconds(5)) }
        #expect(model.snapshot.latestVersion == "9.9.9")
        model.stop()
    }

    @Test func openReportsHandlerErrorsAndFolderIsTheSaveDirectory() {
        let dir = tempDir()
        let model = makeModel(store: StateStore(url: dir.appendingPathComponent("state.json")))
        var opened: [URL] = []
        model.opener = { opened.append($0); return opened.count == 1 ? "no handler" : nil }
        model.open(AppInfo.repoURL)
        #expect(model.snapshot.systemError == L("열지 못했어요: %@", .text("no handler")))
        model.openSaveFolder()
        #expect(model.snapshot.systemError == nil)
        #expect(opened.map(\.path) == [AppInfo.repoURL.path, dir.path])
    }

    @Test func scanRootsUseTheSharedDefaultsKeyAndBuildAFreshReader() async {
        let key = CustomScanRoots.defaultsKey(for: Provider.codex.rawValue)
        let before = UserDefaults.standard.object(forKey: key)
        defer { if let before { UserDefaults.standard.set(before, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) } }
        let model = makeModel(store: StateStore(url: tempDir().appendingPathComponent("state.json")))
        model.scanRootsDebounce = .milliseconds(10)
        model.start()
        let generation = model.stateGeneration
        model.setScanRoots("~/remote-logs/*/codex/sessions", provider: Provider.codex.rawValue)
        #expect(CustomScanRoots.storedValue(for: Provider.codex.rawValue) == "~/remote-logs/*/codex/sessions")
        for _ in 0..<300 where model.stateGeneration == generation { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(model.stateGeneration == generation + 1)
        model.stop()
    }

    @Test func versionBugReportAndLicenseAreLinuxSpecific() throws {
        let root = tempDir()
        let versionFile = root.appendingPathComponent("version.txt")
        try "0.7.0\n".write(to: versionFile, atomically: true, encoding: .utf8)
        #expect(AppInfo.installedVersion(at: versionFile) == "0.7.0")
        #expect(AppInfo.installedVersion(at: nil) == nil)
        let body = AppInfo.bugReportURL.absoluteString.removingPercentEncoding ?? ""
        #expect(body.contains("Linux ")); #expect(!body.contains("macOS"))

        let licenses = root.appendingPathComponent("licenses")
        try FileManager.default.createDirectory(at: licenses, withIntermediateDirectories: true)
        try "Adwaita terms".write(to: licenses.appendingPathComponent("adwaita-swift.txt"), atomically: true, encoding: .utf8)
        try "Meta terms".write(to: licenses.appendingPathComponent("meta.txt"), atomically: true, encoding: .utf8)
        let installed = AppInfo.license(installed: licenses, checkouts: root.appendingPathComponent("none"))
        #expect(installed.contains("## adwaita-swift\n\nAdwaita terms")); #expect(installed.contains("## meta\n\nMeta terms"))
        #expect(!installed.contains("Sparkle")); #expect(installed.contains("PokeTokenBar"))

        let checkouts = root.appendingPathComponent("checkouts/swift-crypto")
        try FileManager.default.createDirectory(at: checkouts, withIntermediateDirectories: true)
        try "Crypto terms".write(to: checkouts.appendingPathComponent("LICENSE.txt"), atomically: true, encoding: .utf8)
        let dev = AppInfo.license(installed: nil, checkouts: root.appendingPathComponent("checkouts"))
        #expect(dev.contains("## swift-crypto\n\nCrypto terms")); #expect(!dev.contains("Sparkle"))
        #expect(!dev.contains("읽지 못했어요"))
    }

    @Test func everyLanguageHasItsOwnCardFile() throws {
        for lang in ["ko", "en", "ja"] { #expect(try CardDB.bundled(lang: lang).packs.count > 100) }
    }
}
#endif
