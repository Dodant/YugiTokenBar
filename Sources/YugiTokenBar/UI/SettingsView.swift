import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

/// 팝오버 안 설정 화면 (상점처럼 요약 위에 겹쳐 그린다)
struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    /// 창 열기 (패치노트·라이선스)
    let open: (String) -> Void
    @State private var checking = false
    @State private var latest: String?
    @State private var checkFailed = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Button { model.showSettings = false } label: {
                    Image(systemName: "chevron.left").font(.body.weight(.semibold)).frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .keyboardShortcut(.cancelAction)
                Text("설정").font(.title3.weight(.semibold))
                Spacer()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    generalSection
                    cardSection
                    updateSection
                    transferSection
                    aboutSection
                }
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
            row {
                labeled("로그인 시 자동 실행", hint: installed ? "Mac에 로그인하면 메뉴바에 바로 떠요" : "설치한 앱(.app)에서만 켤 수 있어요")
                Spacer()
                Toggle("로그인 시 자동 실행", isOn: $launchAtLogin)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(!installed)
                    .onChange(of: launchAtLogin) { setLaunchAtLogin() }
            }
            Divider()
            let unlocked = model.game.state.partnerUnlocked
            row {
                labeled("바탕화면 파트너", hint: unlocked ? "날개 크리보가 바탕화면에서 함께해요. 끌어서 옮기고 누르면 이 패널이 열려요"
                                                    : "「날개 크리보」 카드를 얻으면 파트너로 함께해요")
                Spacer()
                Toggle("바탕화면 파트너", isOn: $model.partnerEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(!unlocked)
            }
            row {
                Text("크기")
                Slider(value: $model.partnerSize, in: PartnerTuning.sizes, step: 16)
                    .controlSize(.small)
                    .disabled(!unlocked || !model.partnerEnabled)
            }
        }
    }

    private var cardSection: some View {
        section("카드") {
            row {
                labeled("중복 카드 자동 판매", hint: "이미 가진 카드가 나오면 바로 코인으로 바꿔요")
                Spacer()
                Toggle("중복 카드 자동 판매", isOn: $model.autoSellDuplicates)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            row {
                let n = model.db.allCIDs.filter { model.game.fusionMaterials($0) != nil }.count
                labeled("융합 몬스터는 융합으로만", hint: "소재를 다 아는 융합 몬스터 \(n)종은 팩·무료 카드에서 안 나와요. 「융합」 카드와 소재를 모아 컬렉션에서 융합하세요")
                Spacer()
                Toggle("융합 몬스터는 융합으로만", isOn: $model.fusionOnly)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
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
                    Text("\(model.db.packs.count)팩 · \(model.db.allCIDs.count.formatted())장").font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                Picker("시대 범위", selection: $model.eraLimit) {
                    ForEach(db.eras, id: \.name) { era in Text("\(era.name)(\(CardDB.eraSummons[era.name] ?? ""))까지").tag(era.name) }
                }
                .labelsHidden()
                .fixedSize()
                .controlSize(.small)
            }
        }
    }

    private var updateSection: some View {
        section("업데이트") {
            row {
                Text("현재 버전")
                Spacer()
                Text(AppInfo.versionText).foregroundStyle(.secondary).monospacedDigit()
            }
            Divider()
            row {
                Text("최신 버전")
                Spacer()
                if checking {
                    ProgressView().controlSize(.small)
                } else {
                    if let latest { Text("v\(latest)").foregroundStyle(.secondary).monospacedDigit() }
                    Button("확인") { checkUpdate() }.controlSize(.small)
                }
            }
            if let latest, !checking {
                Divider()
                if AppInfo.isNewer(latest, than: AppInfo.currentVersion) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("새 버전 v\(latest)이 있어요").font(.callout).foregroundStyle(.orange)
                            Spacer()
                            Link("GitHub에서 받기", destination: AppInfo.repoURL).font(.callout)
                        }
                        Text("git pull && scripts/build-app.sh --install")
                            .font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                } else {
                    row { Text("최신 버전이에요").font(.callout).foregroundStyle(.secondary); Spacer() }
                }
            } else if checkFailed, !checking {
                Divider()
                row { Text("확인하지 못했어요. 네트워크를 확인해 주세요.").font(.callout).foregroundStyle(.secondary); Spacer() }
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
                Text("패치노트")
                Spacer()
                Button("보기") { open("changelog") }.controlSize(.small)
            }
            Divider()
            row {
                Text("GitHub")
                Spacer()
                Link("Dodant/YugiTokenBar", destination: AppInfo.repoURL).font(.callout)
            }
            Divider()
            row {
                labeled("PokeTokenBar 크레딧", hint: "사용량 읽기 코드 · © 2026 chattymin · MIT")
                Spacer()
                Button("라이선스") { open("license") }.controlSize(.small)
            }
        }
    }

    // MARK: 동작

    private func setLaunchAtLogin() {
        let service = SMAppService.mainApp
        guard launchAtLogin != (service.status == .enabled) else { return }
        do {
            try launchAtLogin ? service.register() : service.unregister()
            // 시스템이 승인을 요구하면 로그인 항목 설정을 열어 준다
            if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch {
            launchAtLogin = service.status == .enabled
            alert("로그인 항목을 바꾸지 못했어요", error.localizedDescription, .warning)
        }
    }

    private func checkUpdate() {
        checking = true
        Task {
            latest = await AppInfo.fetchLatestVersion()
            checkFailed = latest == nil
            checking = false
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
            alert("내보내지 못했어요", error.localizedDescription, .warning)
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
            alert("가져오지 못했어요", error.localizedDescription, .warning)
            return
        }
        // 무엇이 바뀌는지 수치로 보여주고 한 번 더 확인받는다
        let current = model.game.state
        let confirm = NSAlert()
        confirm.alertStyle = .warning
        confirm.messageText = "세이브를 바꿀까요?"
        confirm.informativeText = """
            가져올 세이브: 카드 \(envelope.state.distinctOwned)종 · \(coinText(envelope.state.coins))
            (\(envelope.exportedAt.formatted(date: .abbreviated, time: .shortened)), v\(envelope.appVersion))
            지금 세이브: 카드 \(current.distinctOwned)종 · \(coinText(current.coins))

            지금 세이브는 세이브 폴더에 자동 백업돼요.
            """
        confirm.addButton(withTitle: "바꾸기")
        confirm.addButton(withTitle: "취소")
        // 파괴적 동작을 기본 버튼으로 두지 않는다 (Return = 취소)
        confirm.buttons[0].keyEquivalent = ""
        confirm.buttons[1].keyEquivalent = "\r"
        guard confirm.runModal() == .alertFirstButtonReturn else { return }

        do {
            let backup = try model.importSave(envelope)
            alert("가져왔어요", "이전 세이브는 \(backup.lastPathComponent)로 백업했어요.", .informational)
        } catch {
            alert("가져오지 못했어요", error.localizedDescription, .warning)
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

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary).padding(.leading, 4)
            VStack(spacing: 0) { content() }
                .background(.fill.quinary, in: .rect(cornerRadius: 16))
        }
    }

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 10) { content() }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(minHeight: 36)
    }

    private func labeled(_ title: String, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
            Text(hint).font(.caption2).foregroundStyle(.tertiary)
        }
    }
}

/// 패치노트·라이선스 창. `#`/`##` 제목만 크게, 나머지 줄은 인라인 마크다운.
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
                    } else if !line.isEmpty {
                        Text((try? AttributedString(markdown: line)) ?? AttributedString(line))
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
    }
}
