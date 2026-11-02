#if os(macOS)
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

/// 팝오버 안 설정 화면 (상점처럼 요약 위에 겹쳐 그린다)
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    /// 창 열기 (패치노트·라이선스)
    let open: (String) -> Void
    /// 업데이트 확인 상태 (확인 전 / 확인 중 / 최신 버전을 받음 / 실패)
    private enum UpdateCheck { case idle, checking, found(String), failed }
    @State private var update = UpdateCheck.idle
    @State private var language = AppLanguage.stored()
    /// 등록 상태는 화면이 나타날 때 읽는다. 초깃값에서 읽으면 패널이 다시 그려질 때마다(코인 적립 등) launchd 에 묻는다
    @State private var launchAtLogin = false
    /// 추가 스캔 폴더를 고치는 provider 와 그 칸의 글 (UserDefaults `customScanRoots.<id>`)
    @State private var scanProvider = Provider.claude
    @State private var scanRoots = CustomScanRoots.storedValue(for: Provider.claude.rawValue) ?? ""

    /// 이 앱이 끝나길 기다렸다가 같은 실행 파일·인자·환경(YTB_STATE_DIR 등)으로 다시 띄운다. 끝날 때 세이브를 쓰므로 겹쳐 띄우지 않는다
    private func relaunch() {
        guard let exe = Bundle.main.executablePath else { return }
        let sh = Process()
        sh.executableURL = URL(fileURLWithPath: "/bin/sh")
        sh.arguments = ["-c", "while kill -0 \"$0\" 2>/dev/null; do sleep 0.2; done; exec \"$@\"",
                        String(ProcessInfo.processInfo.processIdentifier), exe] + CommandLine.arguments.dropFirst()
        guard (try? sh.run()) != nil else { return }
        NSApp.terminate(nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PanelHeader(title: String(localized: "설정")) { model.screen = .summary }
            // PokeTokenBar 처럼 팝오버 안의 그룹 Form: 고르기(고른 값 + 동그라미 ⌃⌄)·스위치·구분선이 시스템 설정과 같은 네이티브 모양이다.
            // Form 고유 배경은 숨겨 섹션 카드만 팝오버 재질 위에 얹고, 팝오버 여백(16)은 빼서 Form 안쪽 여백만 남긴다
            Form {
                generalSection
                scanSection
                cardSection
                partnerSection
                transferSection
                aboutSection
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .contentMargins(.top, 0, for: .scrollContent)
            .scrollIndicators(.never)
            .padding(.horizontal, -16)
            .panelScrollBottom()
        }
    }

    // MARK: 섹션

    private var generalSection: some View {
        // swift run 바이너리는 .app 이 아니라 로그인 항목으로 등록할 수 없다
        let installed = AppInfo.bundleVersion != nil
        return Section("일반") {
            toggleRow("로그인 시 자동 실행", hint: installed ? "로그인하면 메뉴바에 표시해요" : "설치한 앱에서 켤 수 있어요",
                      isOn: $launchAtLogin)
                .disabled(!installed)
                .onChange(of: launchAtLogin) { setLaunchAtLogin() }
                .onAppear { launchAtLogin = Self.isRegistered(SMAppService.mainApp) }
            Picker(selection: $language) {
                ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text("언어")
                    if language != AppLanguage.launchChoice {
                        Button("다시 열어 적용") { relaunch() }.buttonStyle(.link).font(.caption2)
                    }
                }
            }
            .onChange(of: language) { AppLanguage.store(language) }
            toggleRow("업무 모드", hint: "카드 이미지와 파트너를 숨겨요", isOn: Bindable(model).workMode)
            toggleRow("동작 줄이기", hint: "카드 연출과 화면 전환 애니메이션을 줄여요",
                      isOn: Bindable(model).animationsOff)
            Picker("메뉴바 표시", selection: Bindable(model).menuBarInfo) {
                ForEach(AppModel.MenuBarInfo.allCases) { Text(verbatim: $0.title).tag($0) }
            }
        }
    }

    // ponytail: 원격 머신 로그는 사용자가 rsync 등으로 이 Mac 에 복사해 와야 하고, 동기화가 자정을 넘기면 전날 몫은 적립에서 빠진다.
    // 정식 해결은 원격에서 사용량을 보내 주는 쪽(원격 에이전트·서버)이다.
    /// 기본 위치 밖 로그 폴더. 읽는 쪽은 PokeTokenBar `CustomScanRoots`가 이미 이 키를 읽는다
    private var scanSection: some View {
        Section("추가 스캔 폴더") {
            Picker(selection: $scanProvider) {
                ForEach(UsageView.agents.filter { $0.id != .cursor }, id: \.id) { Text(verbatim: $0.name).tag($0.id) }
            } label: {
                labeled("프로바이더", hint: "원격 머신 로그를 이 Mac에 복사해 온 폴더 등",
                        detail: "기본 위치 밖 로그만 넣어요. 콤마·줄바꿈으로 구분하고 * 와일드카드를 써요. Claude는 projects 폴더, Codex는 sessions 폴더를 넣어요.")
            }
            .onChange(of: scanProvider) { scanRoots = CustomScanRoots.storedValue(for: scanProvider.rawValue) ?? "" }
            VStack(alignment: .leading, spacing: 4) {
                TextField(text: $scanRoots, prompt: Text(verbatim: "~/remote-logs/*/claude/projects"), axis: .vertical) { Text("추가 스캔 폴더") }
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: scanRoots) {
                        UserDefaults.standard.set(scanRoots, forKey: CustomScanRoots.defaultsKey(for: scanProvider.rawValue))
                        LocalUsageReader.invalidateProjectRootsCache()
                    }
                if !scanRoots.isEmpty {
                    Text("찾은 폴더: \(CustomScanRoots.expand(scanRoots).count)").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var partnerSection: some View {
        let unlocked = model.game.state.partnerUnlocked
        return Section {
            toggleRow("바탕화면 파트너", hint: unlocked ? "날개 크리보를 바탕화면에 표시해요"
                                                 : "「날개 크리보」를 얻으면 켤 수 있어요",
                      detail: unlocked ? "끌어서 옮기고, 우클릭으로 숨겨요" : nil,
                      isOn: Bindable(model).partnerEnabled)
                .disabled(!unlocked)
            LabeledContent("크기") {
                Slider(value: Bindable(model).partnerSize, in: PartnerTuning.sizes, step: PartnerTuning.sizeStep)
                    .controlSize(.small)
                    .disabled(!unlocked || !model.partnerEnabled)
            }
        } header: { sectionHeader("파트너", beta: true) }
    }

    private var cardSection: some View {
        let db = model.game.db  // 시대 범위 안만
        let fields = db.allCIDs.filter { db.cards[$0]?.field == true && model.game.copies($0) > 0 }
        let full = model.game.fullDB
        return Section("카드") {
            toggleRow("중복 카드 자동 판매", hint: "새로 나온 중복 카드를 코인으로 바꿔요",
                      detail: "이미 모은 카드는 그대로예요. 오버프레임 그림이 있는 카드는 해금하는 \(Balance.overframeCopies)장까지 남기고, 융합에 필요한 소재도 남겨요.",
                      isOn: Bindable(model).autoSellDuplicates)
            Picker(selection: Bindable(model).fieldBackground) {
                Text("없음").tag(Int?.none)
                ForEach(fields, id: \.self) { Text(verbatim: db.cards[$0]?.name ?? "").tag(Int?.some($0)) }
            } label: {
                labeled("필드 배경", hint: fields.isEmpty ? "필드 마법 카드를 얻으면 고를 수 있어요" : "필드 마법 카드의 그림을 배경으로 써요")
            }
            .disabled(fields.isEmpty)
            Picker(selection: Bindable(model).eraLimit) {
                ForEach(full.eras, id: \.name) { era in eraTitle(era.name).tag(era.name) }
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text("시대 범위")
                        Image(systemName: "questionmark.circle")
                            .foregroundStyle(.secondary)
                            .hoverHint("카드·상점·컬렉션이 설정한 시대까지 나와요.\n시대를 옮겨도 카드는 그대로 남아요.")
                    }
                    Text("\(model.db.packs.count)팩 · \(model.db.allCIDs.count.formatted())장").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var transferSection: some View {
        Section("백업 & 이전") {
            buttonRow("내보내기", action: exportSave) { labeled("세이브 내보내기", hint: "다른 Mac으로 옮기거나 보관할 파일") }
            buttonRow("가져오기", action: importSave) { labeled("세이브 가져오기", hint: "지금 세이브는 먼저 자동 백업돼요") }
            buttonRow("Finder", action: { NSWorkspace.shared.activateFileViewerSelecting([model.saveFolder]) }) {
                labeled("세이브 폴더", hint: "자동 백업도 여기 있어요")
            }
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("버전") {
                HStack(spacing: 10) {
                    Text(AppInfo.versionText).foregroundStyle(.secondary).monospacedDigit()
                    // 개발 빌드는 버전이 정해져 있지 않으니 "(최신)"을 붙이지 않는다
                    if AppInfo.bundleVersion != nil, case .found(let latest) = update,
                       !AppInfo.isNewer(latest, than: AppInfo.currentVersion) {
                        Text("(최신)").font(.caption).foregroundStyle(.secondary)
                    }
                    if case .checking = update {
                        ProgressView().controlSize(.small)
                    } else {
                        glassButton("업데이트 확인") { checkUpdate() }
                    }
                }
            }
            if case .found(let latest) = update,
               AppInfo.isNewer(latest, than: AppInfo.currentVersion) {
                HStack {
                    Text("새 버전 v\(latest)이 있어요").font(.callout).foregroundStyle(Palette.warning)
                    Spacer()
                    Link("GitHub에서 받기", destination: AppInfo.releasesURL).font(.subheadline)
                }
            } else if case .failed = update {
                Text("확인하지 못했어요. 네트워크를 확인해 주세요.").font(.callout).foregroundStyle(.secondary)
            }
            buttonRow("보기", action: { open("changelog") }) { Text("패치노트") }
            buttonRow("Dodant/YugiTokenBar", action: { NSWorkspace.shared.open(AppInfo.repoURL) }) { Text("GitHub Repo") }
            buttonRow("메일 쓰기", action: { NSWorkspace.shared.open(AppInfo.bugReportURL) }) { Text("버그 신고하기") }
            buttonRow("License", action: { open("license") }) {
                labeled("Inspired by [PokeTokenBar](https://github.com/chattymin/PokeTokenBar)", hint: "Usage reading code · © 2026 chattymin · MIT")
            }
            labeled("Card data & images", hint: "[Konami Card Database](https://www.db.yugioh-card.com/yugiohdb/) · [YGOPRODeck](https://ygoprodeck.com/) · [Yugipedia](https://yugipedia.com/)")
            labeled("Unofficial fan project", hint: "Not affiliated with Konami\nCard names, text and images © Konami")
        } header: { Text("정보 & 지원") } footer: {
            Text("Made with Love and Claude").font(.caption2).foregroundStyle(.tertiary).frame(maxWidth: .infinity)
        }
    }

    // MARK: 동작

    /// 승인 대기(.requiresApproval)도 등록된 상태다. 아니면 그 상태에서 끄거나 다시 열 때 해제가 빠진다
    private static func isRegistered(_ service: SMAppService) -> Bool {
        service.status == .enabled || service.status == .requiresApproval
    }

    private func setLaunchAtLogin() {
        let service = SMAppService.mainApp
        guard launchAtLogin != Self.isRegistered(service) else { return }
        do {
            try launchAtLogin ? service.register() : service.unregister()
            // 시스템이 승인을 요구하면 로그인 항목 설정을 열어 준다
            if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch {
            launchAtLogin = Self.isRegistered(service)
            alert(String(localized: "로그인 항목을 바꾸지 못했어요"), error.localizedDescription, .warning)
        }
    }

    private func checkUpdate() {
        // Sparkle 이 켜진 .app 은 Sparkle 창이 확인·내려받기·설치를 맡는다
        if Updater.controller != nil { Updater.checkForUpdates(); return }
        update = .checking
        Task {
            if let latest = await AppInfo.fetchLatestVersion() { update = .found(latest) } else { update = .failed }
        }
    }

    private func exportSave() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = SaveEnvelope.fileName(Date())
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.exportedSave().write(to: url, options: .atomic)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            alert(String(localized: "내보내지 못했어요"), error.localizedDescription, .warning)
        }
    }

    private func importSave() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let envelope: SaveEnvelope
        do { envelope = try SaveEnvelope.decode(Data(contentsOf: url)) } catch {
            alert(String(localized: "가져오지 못했어요"), error.localizedDescription, .warning)
            return
        }
        // 무엇이 바뀌는지 수치로 보여주고 한 번 더 확인받는다
        let current = model.game.state
        let confirm = NSAlert()
        confirm.alertStyle = .warning
        confirm.messageText = String(localized: "세이브를 바꿀까요?")
        confirm.informativeText = String(localized: """
            가져올 세이브: 카드 \(envelope.state.distinctOwned)종 · \(coinText(envelope.state.coins))
            (\(envelope.exportedAt.formatted(date: .abbreviated, time: .shortened)), v\(envelope.appVersion))
            지금 세이브: 카드 \(current.distinctOwned)종 · \(coinText(current.coins))

            지금 세이브는 세이브 폴더에 자동 백업돼요.
            """)
        confirm.addButton(withTitle: String(localized: "바꾸기"))
        confirm.addButton(withTitle: String(localized: "취소"))
        // 파괴적 동작을 기본 버튼으로 두지 않는다 (Return = 취소)
        confirm.buttons[0].keyEquivalent = ""
        confirm.buttons[1].keyEquivalent = "\r"
        guard confirm.runModal() == .alertFirstButtonReturn else { return }

        do {
            let backup = try model.importSave(envelope)
            alert(String(localized: "가져왔어요"), String(localized: "이전 세이브는 \(backup.lastPathComponent)로 백업했어요."), .informational)
        } catch {
            alert(String(localized: "가져오지 못했어요"), error.localizedDescription, .warning)
        }
    }

    private func alert(_ title: String, _ message: String, _ style: NSAlert.Style) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = message
        NSApp.activate()
        alert.runModal()
    }

    // MARK: 공용

    /// 섹션 제목 (β 표시 선택). 글꼴은 Form 이 입힌다
    private func sectionHeader(_ title: LocalizedStringKey, beta: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(title)
            if beta {
                Text(verbatim: "β")
                    .font(.caption2.italic())
                    .foregroundStyle(.tertiary)
                    .hoverHint("베타 기능")  // 메뉴바 패널이라 .help 대신
                    .accessibilityLabel("베타 기능")
            }
        }
    }

    /// 이름·설명 + 오른쪽 스위치 한 줄. VoiceOver 는 스위치에서 설명까지 읽는다
    private func toggleRow(_ title: LocalizedStringKey, hint: LocalizedStringKey, detail: LocalizedStringKey? = nil, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) { labeled(title, hint: hint, detail: detail) }
            .toggleStyle(.switch)
            .controlSize(.small)
            .accessibilityHint(detail ?? hint)
    }

    /// 이름(·설명) + 오른쪽 작은 유리 버튼 한 줄
    private func buttonRow<Label: View>(_ button: LocalizedStringKey, action: @escaping () -> Void, @ViewBuilder label: () -> Label) -> some View {
        LabeledContent(content: { glassButton(button, action: action) }, label: label)
    }

    /// 팝오버의 다른 유리 버튼과 같은 작은 캡슐. Form 전체에 걸면 고르기 동그라미에도 미칠 수 있어 버튼마다 건다
    private func glassButton(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(title, action: action).buttonStyle(.glass).buttonBorderShape(.capsule).controlSize(.small)
    }

    /// 시대 범위 항목 "GX(융합)까지"
    private func eraTitle(_ name: String) -> Text { Text("\(name)(\(CardInfo.summonTitle(CardDB.eraSummons[name] ?? "")))까지") }

    private func labeled(_ title: LocalizedStringKey, hint: LocalizedStringKey, detail: LocalizedStringKey? = nil) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text(title)
                if let detail {
                    Image(systemName: "questionmark.circle")
                        .foregroundStyle(.secondary)
                        .hoverHint(detail)
                        .accessibilityLabel(detail)
                }
            }
            Text(hint).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

/// 패치노트·라이선스 창. `#`/`##` 제목만 크게, `- ` 줄은 • 항목(두 칸 들여 쓴 다음 줄은 같은 항목의 다음 문장), 나머지 줄은 인라인 마크다운.
struct DocView: View {
    let text: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    let line = block[0]
                    if line.hasPrefix("## ") {
                        Text(line.dropFirst(3)).font(.headline).padding(.top, 10)
                    } else if line.hasPrefix("# ") {
                        Text(line.dropFirst(2)).font(.title2.weight(.semibold))
                    } else if line.hasPrefix("- ") {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("•")
                            VStack(alignment: .leading, spacing: 2) {
                                inline(String(line.dropFirst(2)))
                                ForEach(Array(block.dropFirst().enumerated()), id: \.offset) { _, more in inline(more) }
                            }
                        }
                        .padding(.leading, 4)
                    } else if !line.isEmpty {
                        inline(line)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
    }

    /// 줄 묶음: `- ` 항목 밑에 두 칸 들여 쓴 줄은 그 항목에 붙인다
    private var blocks: [[String]] {
        text.components(separatedBy: "\n").reduce(into: []) { acc, line in
            if line.hasPrefix("  "), acc.last?.first?.hasPrefix("- ") == true {
                acc[acc.count - 1].append(line.trimmingCharacters(in: .whitespaces))
            } else {
                acc.append([line])
            }
        }
    }

    /// 긴 항목도 잘리지 않고 창 너비에서 줄을 바꾼다 (선택 가능한 Text 는 한 줄로 줄이기 쉽다)
    private func inline(_ line: String) -> some View {
        Text((try? AttributedString(markdown: line)) ?? AttributedString(line))
            .fixedSize(horizontal: false, vertical: true)
    }
}
#endif
