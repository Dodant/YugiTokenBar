#if os(Linux)
import Adwaita
import Foundation

enum LinuxSection: String, CaseIterable, Identifiable {
    case shop, dex, usage, settings
    var id: String { rawValue }
    @MainActor var title: String {
        switch self {
        case .shop: L("상점")
        case .dex: L("도감")
        case .usage: L("사용량")
        case .settings: L("설정")
        }
    }
}

@MainActor struct LinuxShellView: View {
    let snapshot: LinuxSnapshot
    let model: LinuxModel
    @State private var section: String = LinuxSection.shop.rawValue

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
                } else {
                    Text((LinuxSection(rawValue: section) ?? .shop).title).padding(30)
                }
                if snapshot.refreshing { Text(L("사용량을 읽고 있어요…")) }
                if let error = snapshot.usageError { Text(error).padding() }
                if snapshot.dirty {
                    Text(L("저장하지 못했어요")).padding()
                    Button(L("다시 시도")) { model.retrySave() }
                }
            }
            .topToolbar { HeaderBar.empty() }
            .navigationTitle((LinuxSection(rawValue: section) ?? .shop).title)
        }
        .vexpand()
        .hexpand()
    }
}

private extension Provider {
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
