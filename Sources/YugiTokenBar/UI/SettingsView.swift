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
            ScrollView {
                // 유리 버튼이 여럿이라 한 컨테이너에서 같이 그린다
                GlassEffectContainer { VStack(alignment: .leading, spacing: 16) {
                    generalSection
                    scanSection
                    cardSection
                    partnerSection
                    transferSection
                    aboutSection
                    Text("Made with Love and Claude")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                } }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
            }
            .scrollIndicators(.never)
            .frame(maxHeight: .infinity)
            .panelScrollBottom()
        }
    }

    // MARK: 섹션

    /// 설정의 선택 메뉴 폭. 다 같게 맞추고(항목이 짧아도 `buttonSizing(.flexible)`로 폭을 채워 오른쪽 끝을 맞춘다), 넘치는 항목은 말줄임
    private static let pickerWidth: CGFloat = 150

    private var generalSection: some View {
        // swift run 바이너리는 .app 이 아니라 로그인 항목으로 등록할 수 없다
        let installed = AppInfo.bundleVersion != nil
        return section("일반") {
            toggleRow("로그인 시 자동 실행", hint: installed ? "로그인하면 메뉴바에 표시해요" : "설치한 앱에서 켤 수 있어요",
                      isOn: $launchAtLogin)
                .disabled(!installed)
                .onChange(of: launchAtLogin) { setLaunchAtLogin() }
                .onAppear { launchAtLogin = Self.isRegistered(SMAppService.mainApp) }
            row {
                VStack(alignment: .leading, spacing: 1) {
                    Text("언어")
                    if language != AppLanguage.launchChoice {
                        Button("다시 열어 적용") { relaunch() }.buttonStyle(.link).font(.caption2)
                    }
                }
                Spacer()
                Picker("언어", selection: $language) {
                    ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .controlSize(.small)
                .buttonSizing(.flexible).frame(width: Self.pickerWidth, alignment: .trailing)
                .onChange(of: language) { AppLanguage.store(language) }
            }
            toggleRow("업무 모드", hint: "카드 이미지와 파트너를 숨겨요", isOn: Bindable(model).workMode)
            toggleRow("동작 줄이기", hint: "카드 연출과 화면 전환 애니메이션을 줄여요",
                      isOn: Bindable(model).animationsOff)
            row {
                Text("메뉴바 표시")
                Spacer()
                Picker("메뉴바 표시", selection: Bindable(model).menuBarInfo) {
                    ForEach(AppModel.MenuBarInfo.allCases) { Text(verbatim: $0.title).tag($0) }
                }
                .labelsHidden()
                .controlSize(.small)
                .buttonSizing(.flexible).frame(width: Self.pickerWidth, alignment: .trailing)  // fixedSize 면 가장 긴 항목 폭이 되어 영어 이름이 세 줄로 접힌다
            }
        }
    }

    // ponytail: 원격 머신 로그는 사용자가 rsync 등으로 이 Mac 에 복사해 와야 하고, 동기화가 자정을 넘기면 전날 몫은 적립에서 빠진다.
    // 정식 해결은 원격에서 사용량을 보내 주는 쪽(원격 에이전트·서버)이다.
    /// 기본 위치 밖 로그 폴더. 읽는 쪽은 PokeTokenBar `CustomScanRoots`가 이미 이 키를 읽는다
    private var scanSection: some View {
        section("추가 스캔 폴더") {
            row {
                labeled("프로바이더", hint: "원격 머신 로그를 이 Mac에 복사해 온 폴더 등",
                        detail: "기본 위치 밖 로그만 넣어요. 콤마·줄바꿈으로 구분하고 * 와일드카드를 써요. Claude는 projects 폴더, Codex는 sessions 폴더를 넣어요.")
                Spacer()
                Picker("프로바이더", selection: $scanProvider) {
                    ForEach(UsageView.agents.filter { $0.id != .cursor }, id: \.id) { Text(verbatim: $0.name).tag($0.id) }
                }
                .labelsHidden()
                .controlSize(.small)
                .buttonSizing(.flexible).frame(width: Self.pickerWidth, alignment: .trailing)
                .onChange(of: scanProvider) { scanRoots = CustomScanRoots.storedValue(for: scanProvider.rawValue) ?? "" }
            }
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
            .padding(.horizontal, 12).padding(.bottom, 8)
        }
    }

    private var partnerSection: some View {
        let unlocked = model.game.state.partnerUnlocked
        return section("파트너", beta: true) {
            toggleRow("바탕화면 파트너", hint: unlocked ? "날개 크리보를 바탕화면에 표시해요"
                                                 : "「날개 크리보」를 얻으면 켤 수 있어요",
                      detail: unlocked ? "끌어서 옮기고, 우클릭으로 숨겨요" : nil,
                      isOn: Bindable(model).partnerEnabled)
                .disabled(!unlocked)
            row {
                Text("크기")
                Slider(value: Bindable(model).partnerSize, in: PartnerTuning.sizes, step: PartnerTuning.sizeStep)
                    .controlSize(.small)
                    .disabled(!unlocked || !model.partnerEnabled)
            }
        }
    }

    private var cardSection: some View {
        section("카드") {
            toggleRow("중복 카드 자동 판매", hint: "새로 나온 중복 카드를 코인으로 바꿔요",
                      detail: "이미 모은 카드는 그대로예요. 오버프레임 그림이 있는 카드는 해금하는 \(Balance.overframeCopies)장까지 남기고, 융합에 필요한 소재도 남겨요.",
                      isOn: Bindable(model).autoSellDuplicates)
            row {
                let db = model.game.db  // 시대 범위 안만
                let fields = db.allCIDs.filter { db.cards[$0]?.field == true && model.game.copies($0) > 0 }
                labeled("필드 배경", hint: fields.isEmpty ? "필드 마법 카드를 얻으면 고를 수 있어요" : "필드 마법 카드의 그림을 배경으로 써요")
                Spacer()
                Picker("필드 배경", selection: Bindable(model).fieldBackground) {
                    Text("없음").tag(Int?.none)
                    ForEach(fields, id: \.self) { Text(verbatim: db.cards[$0]?.name ?? "").tag(Int?.some($0)) }
                }
                .labelsHidden()
                .buttonSizing(.flexible).frame(width: Self.pickerWidth, alignment: .trailing)  // 긴 카드 이름은 말줄임 (fixedSize 면 이름·설명이 폭 0으로 눌린다)
                .controlSize(.small)
                .disabled(fields.isEmpty)
            }
            row {
                let db = model.game.fullDB
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text("시대 범위")
                        Image(systemName: "questionmark.circle")
                            .foregroundStyle(.secondary)
                            .hoverHint("카드·상점·컬렉션이 설정한 시대까지 나와요.\n시대를 옮겨도 카드는 그대로 남아요.")
                    }
                    Text("\(model.db.packs.count)팩 · \(model.db.allCIDs.count.formatted())장").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("시대 범위", selection: Bindable(model).eraLimit) {
                    ForEach(db.eras, id: \.name) { era in Text("\(era.name)(\(CardInfo.summonTitle(CardDB.eraSummons[era.name] ?? "")))까지").tag(era.name) }
                }
                .labelsHidden()
                .buttonSizing(.flexible).frame(width: Self.pickerWidth, alignment: .trailing)
                .controlSize(.small)
            }
        }
    }

    private var transferSection: some View {
        section("백업 & 이전") {
            row {
                labeled("세이브 내보내기", hint: "다른 Mac으로 옮기거나 보관할 파일")
                Spacer()
                Button("내보내기") { exportSave() }.controlSize(.small)
            }
            Divider()
            row {
                labeled("세이브 가져오기", hint: "지금 세이브는 먼저 자동 백업돼요")
                Spacer()
                Button("가져오기") { importSave() }.controlSize(.small)
            }
            Divider()
            row {
                labeled("세이브 폴더", hint: "자동 백업도 여기 있어요")
                Spacer()
                Button("Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.saveFolder]) }.controlSize(.small)
            }
        }
    }

    private var aboutSection: some View {
        section("정보 & 지원") {
            row {
                Text("버전")
                Spacer()
                Text(AppInfo.versionText).foregroundStyle(.secondary).monospacedDigit()
                // 개발 빌드는 버전이 정해져 있지 않으니 "(최신)"을 붙이지 않는다
                if AppInfo.bundleVersion != nil, case .found(let latest) = update,
                   !AppInfo.isNewer(latest, than: AppInfo.currentVersion) {
                    Text("(최신)").font(.caption).foregroundStyle(.secondary)
                }
                if case .checking = update {
                    ProgressView().controlSize(.small)
                } else {
                    Button("업데이트 확인") { checkUpdate() }.controlSize(.small)
                }
            }
            if case .found(let latest) = update,
               AppInfo.isNewer(latest, than: AppInfo.currentVersion) {
                Divider()
                row {
                    Text("새 버전 v\(latest)이 있어요").font(.callout).foregroundStyle(Palette.warning)
                    Spacer()
                    Link("GitHub에서 받기", destination: AppInfo.releasesURL).font(.subheadline)
                }
            } else if case .failed = update {
                Divider()
                row { Text("확인하지 못했어요. 네트워크를 확인해 주세요.").font(.callout).foregroundStyle(.secondary); Spacer() }
            }
            Divider()
            row {
                Text("패치노트")
                Spacer()
                Button("보기") { open("changelog") }.controlSize(.small)
            }
            Divider()
            row {
                Text("GitHub Repo")
                Spacer()
                Button("Dodant/YugiTokenBar") { NSWorkspace.shared.open(AppInfo.repoURL) }.controlSize(.small)
            }
            Divider()
            row {
                Text("버그 신고하기")
                Spacer()
                Button("메일 쓰기") { NSWorkspace.shared.open(AppInfo.bugReportURL) }.controlSize(.small)
            }
            Divider()
            row {
                labeled("Inspired by [PokeTokenBar](https://github.com/chattymin/PokeTokenBar)", hint: "Usage reading code · © 2026 chattymin · MIT")
                Spacer()
                Button("License") { open("license") }.controlSize(.small)
            }
            Divider()
            row {
                labeled("Card data & images", hint: "[Konami Card Database](https://www.db.yugioh-card.com/yugiohdb/) · [YGOPRODeck](https://ygoprodeck.com/) · [Yugipedia](https://yugipedia.com/)")
                Spacer()
            }
            Divider()
            row {
                labeled("Unofficial fan project", hint: "Not affiliated with Konami\nCard names, text and images © Konami")
                Spacer()
            }
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

    private func section<Content: View>(_ title: LocalizedStringKey, beta: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                if beta {
                    Text(verbatim: "β")
                        .font(.caption2.italic())
                        .foregroundStyle(.tertiary)
                        .hoverHint("베타 기능")  // 메뉴바 패널이라 .help 대신
                        .accessibilityLabel("베타 기능")
                }
            }
            .padding(.leading, 4)
            VStack(spacing: 0) { content() }
                .background(.fill.quinary, in: .rect(cornerRadius: 16))  // 팝오버 요약의 카드(panelCard)와 같은 바탕
        }
    }

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 10) { content() }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(minHeight: 36)
    }

    /// 이름·설명 + 오른쪽 스위치 한 줄. VoiceOver 는 스위치에서 설명까지 읽는다
    private func toggleRow(_ title: LocalizedStringKey, hint: LocalizedStringKey, detail: LocalizedStringKey? = nil, isOn: Binding<Bool>) -> some View {
        row {
            labeled(title, hint: hint, detail: detail)
            Spacer()
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityHint(detail ?? hint)
        }
    }

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
