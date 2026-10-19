#if os(Linux)
import Adwaita
import Foundation

enum LinuxSection: String, CaseIterable, Identifiable {
    case shop, dex, usage, settings
    var id: String { rawValue }
    @MainActor var title: String {
        switch self {
        case .shop: L("상점")
        case .dex: L("컬렉션")
        case .usage: L("사용량")
        case .settings: L("설정")
        }
    }
}

@MainActor struct LinuxShellView: View {
    let snapshot: LinuxSnapshot
    let model: LinuxModel
    var restart: () -> Void = {}
    @State private var section: String = LinuxSection.shop.rawValue
    @State private var rescueExporter: Signal = .init()

    var view: Body {
        NavigationSplitView {
            VStack {
                Text(L("코인 %@", .text(coinText(snapshot.game.state.coins)))).padding()
                Text(snapshot.usageHeading()).padding()
                ForEach(Provider.allCases, id: \.rawValue) { provider in
                    Text("\(provider.linuxDisplayName)  \(shortTokens(snapshot.todayDetail[provider.rawValue]?.total ?? 0))")
                }
                List(LinuxSection.allCases, selection: $section) { item in
                    Button(item.title) {
                        if item == .shop { model.closeOpening() }
                        if item == .usage { model.loadHistory() }
                        if item == .settings { model.checkForUpdate() }
                        section = item.rawValue
                    }.linuxSmokeID("sidebar-\(item.rawValue)")
                    .style("flat").hexpand()
                }.sidebarStyle()
            }
            .navigationTitle("YugiTokenBar")
        } content: {
            VStack {
                if section == LinuxSection.shop.rawValue {
                    LinuxShopView(snapshot: snapshot, model: model)
                } else if section == LinuxSection.dex.rawValue {
                    LinuxDexView(snapshot: snapshot, model: model)
                } else if section == LinuxSection.usage.rawValue {
                    LinuxUsageView(snapshot: snapshot, model: model)
                } else {
                    LinuxSettingsView(snapshot: snapshot, model: model, restart: restart)
                }
                if snapshot.refreshing { Text(L("사용량을 읽고 있어요…")) }
                if let error = snapshot.usageError { Text(error).padding() }
                if snapshot.dirty {
                    Text(L("저장하지 못했어요")).padding()
                    HStack(spacing: 10) {
                        Button(L("다시 시도")) { model.retrySave() }.linuxSmokeID("dirty-retry")
                        Button(L("내보내기")) { rescueExporter.signal() }.linuxSmokeID("dirty-export")
                        Button(L("폴더 열기")) { model.openSaveFolder() }.linuxSmokeID("dirty-open-folder")
                    }.halign(.center).padding()
                    if let error = snapshot.systemError { Text(error).wrap().style("error") }
                }
            }
            .linuxSaveExporter($rescueExporter, model: model)
            .topToolbar { HeaderBar.empty() }
            .navigationTitle((LinuxSection(rawValue: section) ?? .shop).title)
        }
        .vexpand()
        .hexpand()
    }
}

extension Provider {
    var linuxDisplayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .gemini: "Gemini"
        case .grok: "Grok"
        case .pi: "Pi"
        case .omp: "oh-my-pi"
        case .cursor: "Cursor"
        }
    }
}
#endif
