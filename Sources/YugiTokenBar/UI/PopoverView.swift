import SwiftUI

struct PopoverView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // ponytail: MenuBarExtra(.window) 패널은 내용 높이가 바뀌면 다시 그리지 못해 깨진다 → 상점·개봉·설정은 요약 크기 안에 겹쳐 그려 높이를 고정
        let covered = model.showShop || model.showSettings || model.showOpening
        return summary
            .opacity(covered ? 0 : 1)
            .allowsHitTesting(!covered)
            .overlay {
                if model.showOpening { OpeningView() }
                else if model.showShop { ShopView() }
                else if model.showSettings { SettingsView(open: show) }
            }
            .padding(16)
            .frame(width: 340)
    }

    // 패널 자체가 Liquid Glass 라서 내용에는 유리를 겹치지 않는다(겹치면 뒤 배경 색이 번져 탁해짐).
    private var summary: some View {
        let game = model.game
        let state = game.state
        return VStack(alignment: .leading, spacing: 16) {
            header(state)

            VStack(alignment: .leading, spacing: 8) {
                caption("최근 획득")
                HStack(spacing: 9) {
                    ForEach(Array(state.log.prefix(5).enumerated()), id: \.offset) { _, entry in
                        CardImageView(db: game.db, cid: entry.cid)
                            .frame(width: 54)
                            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                            .help(game.db.cards[entry.cid]?.name ?? "")
                    }
                    if state.log.isEmpty {
                        Text("아직 카드가 없어요").font(.callout).foregroundStyle(.secondary)
                    }
                }
                .frame(height: 79)
            }

            if state.pendingFree > 0 {
                FreeRow(count: state.pendingFree) { model.openFree() }
                    .padding(12)
                    .background(.fill.quinary, in: .rect(cornerRadius: 16))
            }

            PackRow(index: game.lastBoughtPack)
                .padding(12)
                .background(.fill.quinary, in: .rect(cornerRadius: 16))

            VStack(spacing: 2) {
                MenuRow(title: "상점", systemImage: "bag", trailing: nil, chevron: true) { model.showShop = true }
                MenuRow(title: "컬렉션", systemImage: "square.stack.3d.up",
                        trailing: "\(game.ownedDistinct) / \(game.db.allCIDs.count)", chevron: true) { show("dex") }
                Divider().padding(.horizontal, 10).padding(.vertical, 4)
                UsageView()
                Divider().padding(.horizontal, 10).padding(.vertical, 4)
                MenuRow(title: "설정", systemImage: "gearshape", trailing: nil, chevron: true) { model.showSettings = true }
                MenuRow(title: "종료", systemImage: "power", trailing: "⌘Q", chevron: false) { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .padding(.horizontal, -8)
        }
    }

    private func header(_ state: GameState) -> some View {
        let left = Balance.tokensPerFreeCard - state.dropProgress
        return HStack(alignment: .center, spacing: 10) {
            Text(coinText(state.coins))
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                caption("다음 무료 카드")
                Text(shortTokens(left)).font(.callout.weight(.medium)).monospacedDigit()
            }
            Gauge(value: Double(state.dropProgress), in: 0...Double(Balance.tokensPerFreeCard)) {
                Image(systemName: "gift.fill")
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(.accentColor)
            .scaleEffect(0.75)
            .frame(width: 44, height: 44)
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.caption.weight(.medium)).foregroundStyle(.secondary)
    }

    private func show(_ id: String) {
        openWindow(id: id)
        // activate 는 다른 앱 뒤에 창을 둘 수 있어서 창을 직접 앞으로 꺼낸다
        NSApp.activate()
        let title = ["dex": "컬렉션", "changelog": "패치노트", "license": "라이선스"][id]
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first(where: { $0.title == title }) else { return }
            window.orderFrontRegardless()
            window.makeKey()
        }
    }
}

/// 쌓인 무료 카드. 누르면 최대 5장씩 연다.
private struct FreeRow: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "gift.fill").font(.title2).foregroundStyle(.tint).frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("무료 카드 \(count)장").font(.callout.weight(.medium)).monospacedDigit()
                Text("토큰으로 모은 카드예요").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button(count > Balance.freeOpenBatch ? "\(Balance.freeOpenBatch)장 열기" : "열기", action: action)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
        }
    }
}

/// 제어 센터·Wi-Fi 메뉴 같은 한 줄 버튼. 마우스를 올리면 배경이 생긴다.
private struct MenuRow: View {
    let title: String
    let systemImage: String
    let trailing: String?
    let chevron: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage).frame(width: 20).foregroundStyle(.secondary)
                Text(title)
                Spacer()
                if let trailing { Text(trailing).foregroundStyle(.secondary).monospacedDigit() }
                if chevron { Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary) }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(hover ? AnyShapeStyle(.fill.tertiary) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// 코인 표기: ⓒ 1,000
func coinText(_ n: Int) -> String { "ⓒ \(n.formatted())" }

func shortTokens(_ n: Int) -> String {
    n >= 1_000_000 ? String(format: "%.1fM", Double(n) / 1e6) : String(format: "%.0fK", Double(n) / 1e3)
}
