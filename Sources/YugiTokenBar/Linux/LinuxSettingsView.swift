#if os(Linux)
import Adwaita
import Foundation

extension AnyView {
    /// Save-file chooser shared by Settings and the unsaved-progress banner.
    @MainActor func linuxSaveExporter(_ signal: Binding<Signal>, model: LinuxModel) -> AnyView {
        fileExporter(open: signal, initialName: SaveEnvelope.fileName(Date()), title: L("세이브 내보내기"),
                     onSave: { model.export(to: $0) })
    }
}

private struct EraChoice { let name: String; let label: String }

@MainActor struct LinuxSettingsView: View {
    let snapshot: LinuxSnapshot
    let model: LinuxModel
    @State private var importer: Signal = .init()
    @State private var exporter: Signal = .init()
    var restart: () -> Void = {}
    @State private var language = AppLanguage.stored().rawValue
    @State private var scanProvider = Provider.claude.rawValue
    @State private var scanRoots = CustomScanRoots.storedValue(for: Provider.claude.rawValue) ?? ""
    @State private var showChangelog = false
    @State private var showLicense = false
    /// Read once when a dialog opens; redraws (60 s refresh) must not re-read the files.
    @State private var dialogText = ""

    @ViewBuilder private func row(_ title: String, hint: String? = nil, @ViewBuilder control: () -> Body = { [] }) -> Body {
        let trailing = control()
        HStack(spacing: 10) {
            VStack(spacing: 2) {
                Text(title).halign(.start)
                if let hint { Text(hint).wrap().halign(.start).style("dim-label") }
            }.hexpand().halign(.start)
            trailing
        }
    }

    private var scanProviders: [Provider] { Provider.allCases.filter { $0 != .cursor } }

    @ViewBuilder private var generalGroup: Body {
        VStack(spacing: 10) {
            Text(L("일반")).style("title-3").halign(.start)
            row(L("언어")) {
                DropDown(selection: Binding(get: { language }, set: { value in
                    guard let choice = AppLanguage(rawValue: value), value != language else { return }
                    language = value; AppLanguage.store(choice)
                }), values: AppLanguage.allCases, id: \.rawValue, description: \.title).linuxSmokeID("settings-language")
            }
            if language != AppLanguage.launchChoice.rawValue {
                Button(L("다시 열어 적용")) { restart() }.linuxSmokeID("settings-restart").halign(.start)
            }
            if let error = snapshot.restartError { Text(error).wrap().halign(.start).style("error") }
        }
    }

    @ViewBuilder private var gameGroup: Body {
        let game = snapshot.game
        let eras = game.fullDB.eras
        VStack(spacing: 10) {
            Text(L("카드")).style("title-3").halign(.start)
            row(L("중복 카드 자동 판매"), hint: L("새로 나온 중복 카드를 코인으로 바꿔요")) {
                CheckButton().active(Binding(get: { snapshot.game.state.autoSellDuplicates },
                                             set: { model.setAutoSellDuplicates($0) })).valign(.center)
                    .linuxSmokeID("settings-autosell")
            }
            row(L("시대 범위"), hint: L("%lld팩 · %@장", .int(game.db.packs.count), .text(game.db.allCIDs.count.formatted()))) {
                DropDown(selection: Binding(get: { snapshot.game.state.eraLimit }, set: { model.setEraLimit($0) }),
                         values: eras.map { EraChoice(name: $0.name, label: L("%@(%@)까지", .text($0.name), .text(CardInfo.summonTitle(CardDB.eraSummons[$0.name] ?? "")))) },
                         id: \.name, description: \.label)
                    .linuxSmokeID("settings-era")
            }
        }
    }

    @ViewBuilder private var scanGroup: Body {
        VStack(spacing: 10) {
            Text(L("추가 스캔 폴더")).style("title-3").halign(.start)
            row(L("프로바이더"), hint: L("기본 위치 밖 로그만 넣어요. 콤마·줄바꿈으로 구분하고 * 와일드카드를 써요. Claude는 projects 폴더, Codex는 sessions 폴더를 넣어요.")) {
                DropDown(selection: Binding(get: { scanProvider }, set: { value in
                    scanProvider = value; scanRoots = CustomScanRoots.storedValue(for: value) ?? ""
                }), values: scanProviders, id: \.rawValue, description: \.linuxDisplayName).linuxSmokeID("settings-scan-provider")
            }
            Entry("~/remote-logs/*/claude/projects", text: Binding(get: { scanRoots }, set: { value in
                guard value != scanRoots else { return }
                scanRoots = value; model.setScanRoots(value, provider: scanProvider)
            })).linuxSmokeID("settings-scan-roots")
            if !scanRoots.isEmpty {
                Text(L("찾은 폴더: %lld", .int(CustomScanRoots.expand(scanRoots).count))).style("dim-label").halign(.start)
            }
            Text(L("셸 설정 파일에서만 내보낸 경로는 Flatpak 앱이 찾지 못할 수 있어요. Flatpak 앱은 홈 폴더 안만 볼 수 있어요."))
                .wrap().halign(.start).style("dim-label")
        }
    }

    @ViewBuilder private var aboutGroup: Body {
        let latest = snapshot.latestVersion.flatMap { AppInfo.isNewer($0, than: AppInfo.currentVersion) ? $0 : nil }
        VStack(spacing: 10) {
            Text(L("정보 & 지원")).style("title-3").halign(.start)
            row(L("버전")) { Text(AppInfo.versionText) }
            if let latest {
                row(L("새 버전 v%@이 있어요", .text(latest))) {
                    Button(L("GitHub에서 받기")) { model.open(AppInfo.releasesURL) }.linuxSmokeID("settings-releases")
                }
            }
            row(L("패치노트")) { Button(L("보기")) { dialogText = AppInfo.changelog; showChangelog = true }.linuxSmokeID("settings-changelog") }
            row("GitHub Repo") { Button("Dodant/YugiTokenBar") { model.open(AppInfo.repoURL) }.linuxSmokeID("settings-repo") }
            row(L("버그 신고하기")) { Button(L("메일 쓰기")) { model.open(AppInfo.bugReportURL) }.linuxSmokeID("settings-bug") }
            row("Inspired by PokeTokenBar", hint: "Usage reading code · © 2026 chattymin · MIT") {
                Button("License") { dialogText = AppInfo.license; showLicense = true }.linuxSmokeID("settings-license")
            }
            row("Card data & images", hint: "Konami Card Database · YGOPRODeck · Yugipedia")
            row("Unofficial fan project", hint: "Not affiliated with Konami\nCard names, text and images © Konami")
            if let error = snapshot.systemError { Text(error).wrap().halign(.start).style("error") }
            Text("Made with Love and Claude").style("dim-label").padding()
        }
    }

    var view: Body {
        ScrollView {
            VStack(spacing: 24) {
                generalGroup
                gameGroup
                scanGroup
                transferGroup
                aboutGroup
            }.padding(20).valign(.start)
        }.vexpand()
        .linuxSaveExporter($exporter, model: model)
        .fileImporter(open: $importer, filters: [.mimeType("application/json")], title: L("세이브 가져오기"),
                      onOpen: { model.prepareImport(at: $0) })
        .dialog(visible: $showChangelog, title: L("패치노트"), id: "changelog", width: 640, height: 520) {
            if showChangelog { ScrollView { Text(dialogText).wrap().halign(.start).padding() }.vexpand() }
        }
        .dialog(visible: $showLicense, title: "License", id: "license", width: 640, height: 520) {
            if showLicense { ScrollView { Text(dialogText).wrap().halign(.start).padding() }.vexpand() }
        }
        .dialog(visible: Binding(get: { snapshot.pendingImport != nil }, set: { if !$0 { model.cancelImport() } }),
                title: L("세이브를 바꿀까요?"), id: "import", width: 420) { importDialog }
    }

    @ViewBuilder private var transferGroup: Body {
        VStack(spacing: 10) {
            Text(L("백업 & 이전")).style("title-3").halign(.start)
            HStack(spacing: 10) {
                Button(L("내보내기")) { exporter.signal() }.linuxSmokeID("settings-export")
                Button(L("가져오기")) { importer.signal() }.linuxSmokeID("settings-import")
            }.halign(.start)
            Text(L("지금 세이브는 먼저 자동 백업돼요")).style("dim-label").halign(.start)
            if let message = snapshot.transferMessage { Text(message).wrap().halign(.start) }
            if let error = snapshot.transferError { Text(error).wrap().halign(.start).style("error") }
            row(L("세이브 폴더"), hint: L("자동 백업도 여기 있어요")) {
                Button(L("폴더 열기")) { model.openSaveFolder() }.linuxSmokeID("settings-folder")
            }
        }
    }

    @ViewBuilder private var importDialog: Body {
            VStack(spacing: 10) {
                if let pending = snapshot.pendingImport {
                    let current = snapshot.game.state, incoming = pending.envelope
                    Text(L("가져올 세이브: 카드 %lld종 · %@\n(%@, v%@)\n지금 세이브: 카드 %lld종 · %@\n\n지금 세이브는 세이브 폴더에 자동 백업돼요.",
                           .int(incoming.state.distinctOwned), .text(coinText(incoming.state.coins)),
                           .text(stamp(incoming.exportedAt, "yyyy-MM-dd HH:mm")), .text(incoming.appVersion),
                           .int(current.distinctOwned), .text(coinText(current.coins)))).wrap().padding()
                }
                if let error = snapshot.transferError { Text(error).wrap().style("error") }
                HStack(spacing: 10) {
                    Button(L("취소")) { model.cancelImport() }.linuxSmokeID("import-cancel")
                    Button(L("바꾸기")) { model.confirmImport() }.linuxSmokeID("import-confirm")
                }.padding()
            }
    }
}
#endif
