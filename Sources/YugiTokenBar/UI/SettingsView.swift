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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PanelHeader(title: String(localized: "설정")) { model.screen = .summary }
            ScrollView {
                // 유리 버튼이 여럿이라 한 컨테이너에서 같이 그린다
                GlassEffectContainer { VStack(alignment: .leading, spacing: 16) {
                    generalSection
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
                        Text("다시 시작하면 적용돼요").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Picker("언어", selection: $language) {
                    ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
                .onChange(of: language) { AppLanguage.store(language) }
            }
            toggleRow("업무 모드", hint: "카드 이미지와 파트너를 숨겨요", isOn: Bindable(model).workMode)
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
                      detail: "이미 모은 카드는 그대로예요. 융합 전용 모드에서는 필요한 소재도 남겨요.",
                      isOn: Bindable(model).autoSellDuplicates)
            let n = model.db.fusionCount
            toggleRow("융합 몬스터는 융합으로만", hint: "융합 몬스터 \(n)종을 팩 대신 융합으로 얻어요",
                      detail: "대상 카드는 팩·무료 카드에서 나오지 않아요. 「융합」 카드와 소재를 모아 컬렉션에서 만드세요.",
                      isOn: Bindable(model).fusionOnly)
            toggleRow("애니메이션 끄기", hint: "카드를 연출 없이 바로 보여줘요",
                      isOn: Bindable(model).animationsOff)
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
                .fixedSize()
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

/// 패치노트·라이선스 창. `#`/`##` 제목만 크게, `- ` 줄은 • 항목(둘째 줄부터 들여쓰기), 나머지 줄은 인라인 마크다운.
struct DocView: View {
    let text: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                    if line.hasPrefix("## ") {
                        Text(line.dropFirst(3)).font(.headline).padding(.top, 10)
                    } else if line.hasPrefix("# ") {
                        Text(line.dropFirst(2)).font(.title2.weight(.semibold))
                    } else if line.hasPrefix("- ") {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("•")
                            inline(String(line.dropFirst(2)))
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

    private func inline(_ line: String) -> Text {
        Text((try? AttributedString(markdown: line)) ?? AttributedString(line))
    }
}
