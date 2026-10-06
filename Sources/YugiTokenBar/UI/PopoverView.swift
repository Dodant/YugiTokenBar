import SwiftUI

struct PopoverView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.lessMotion) private var lessMotion
    /// 무료 팩·무료 카드 줄이 보이는지. 덮여 있는 동안(개봉·상점·설정)에는 새로 생기는 줄은 미뤘다가 돌아왔을 때 보이고
    /// (팩을 까다 무료 팩이 생겨도 개봉 화면이 늘어나지 않게), 다 써서 사라지는 줄은 바로 뺀다(마지막 무료 팩을 열면 원래 높이로)
    @State private var freeRows: (pack: Bool, card: Bool)?

    var body: some View {
        // ponytail: MenuBarExtra(.window) 패널은 내용 높이가 바뀌면 다시 그리지 못해 깨진다 → 상점·개봉·설정은 요약 크기 안에 겹쳐 그려 높이를 고정
        let covered = model.showShop || model.showSettings || model.showOpening
        return summary
            .opacity(covered ? 0 : 1)
            .allowsHitTesting(!covered)
            .overlay {
                // 개봉마다 새 뷰로 만들어 뒤집기·레어 연출 상태를 처음부터 시작한다
                if model.showOpening { OpeningView().id(model.openingID) }
                else if model.showShop { ShopView() }
                else if model.showSettings { SettingsView(open: show) }
            }
            .padding(16)
            .frame(width: 340)
            .onChange(of: [covered, model.game.state.freePacks > 0, model.game.state.pendingFree > 0], initial: true) {
                let now = (pack: model.game.state.freePacks > 0, card: model.game.state.pendingFree > 0)
                freeRows = covered ? (now.pack && freeRows?.pack ?? false, now.card && freeRows?.card ?? false) : now
            }
    }

    // 패널 자체가 Liquid Glass 라서 내용에는 유리를 겹치지 않는다(겹치면 뒤 배경 색이 번져 탁해짐).
    private var summary: some View {
        let game = model.game
        let state = game.state
        return VStack(alignment: .leading, spacing: 16) {
            header(state)

            // ponytail: 덮인 화면(개봉·상점·설정) 중에 생기면 패널이 한 줄 늘어난다. 저장 실패는 드물어서 freeRows 처럼 미루지 않는다
            if let error = model.saveError {
                FreeRow(systemImage: "exclamationmark.triangle.fill", title: "진행 상황을 저장하지 못했어요",
                        hint: error, button: "폴더 열기") { NSWorkspace.shared.activateFileViewerSelecting([model.saveFolder]) }
                    .padding(12)
                    .background(.fill.quinary, in: .rect(cornerRadius: 16))
                    .tint(.orange)
            }

            VStack(alignment: .leading, spacing: 8) {
                caption("최근 획득")
                HStack(spacing: 9) {
                    ForEach(Array(state.log.prefix(5).enumerated()), id: \.offset) { _, entry in
                        CardImageView(db: game.db, cid: entry.cid)
                            .frame(width: 54)
                            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                            .cardTilt(tier: game.db.tier(entry.cid), angleScale: 0.5)
                            .hoverHint(game.db.cards[entry.cid]?.name ?? "")
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(game.db.cards[entry.cid]?.name ?? "")
                            .accessibilityAddTraits(.isImage)
                    }
                    if state.log.isEmpty {
                        Text("아직 카드가 없어요").font(.callout).foregroundStyle(.secondary)
                    }
                }
                .frame(height: 79)
            }

            if freeRows?.pack ?? (state.freePacks > 0) {
                FreeRow(systemImage: "shippingbox.fill", title: "무료 팩 \(state.freePacks)개",
                        hint: "\(Balance.packsPerFreePack)팩마다 랜덤 부스터 1팩", button: "열기") { model.openFreePack() }
                    .padding(12)
                    .background(.fill.quinary, in: .rect(cornerRadius: 16))
            }

            if freeRows?.card ?? (state.pendingFree > 0) {
                FreeRow(systemImage: "gift.fill", title: "무료 카드 \(state.pendingFree)장", hint: "토큰으로 모은 카드예요",
                        button: state.pendingFree > Balance.freeOpenBatch ? "\(Balance.freeOpenBatch)장 열기" : "열기") { model.openFree() }
                    .padding(12)
                    .background(.fill.quinary, in: .rect(cornerRadius: 16))
            }

            PackRow(index: game.lastBoughtPack)
                .padding(12)
                .background(.fill.quinary, in: .rect(cornerRadius: 16))

            VStack(spacing: 2) {
                MenuRow(title: "상점", systemImage: "bag", trailing: nil, chevron: true) { model.showShop = true }
                MenuRow(title: "컬렉션", systemImage: "square.stack.3d.up",
                        trailing: "\(game.ownedDistinct) / \(game.db.allCIDs.count)", chevron: false, opensWindow: true) { show("dex") }
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
                .animation(lessMotion ? nil : .default, value: state.coins)  // 적립·구매가 withAnimation 밖이라 여기서 건다
                .hoverHint("토큰 \(Balance.tokensPerCoin.formatted()) = \(coinText(1))")
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                caption("다음 무료 카드 · 팩")
                Text("\(shortTokens(left)) · \(state.packStamp)/\(Balance.packsPerFreePack)")
                    .font(.callout.weight(.medium)).monospacedDigit()
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
        // 컬렉션은 navigationTitle 로 제목이 팩 이름으로 바뀌므로 제목 대신 Scene id(NSWindow.identifier)로 찾는다
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix(id) == true }) else { return }
            window.orderFrontRegardless()
            window.makeKey()
        }
    }
}

/// 패널 안 화면(상점·설정·개봉) 머리말: 뒤로(esc) · 제목 · 오른쪽 내용.
struct PanelHeader<Trailing: View>: View {
    let title: String
    let back: () -> Void
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 6) {
            Button(action: back) {
                Image(systemName: "chevron.left").font(.body.weight(.semibold)).frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("뒤로")
            Text(title).font(.title3.weight(.semibold)).lineLimit(1)
            Spacer()
            trailing
        }
    }
}

extension PanelHeader where Trailing == EmptyView {
    init(title: String, back: @escaping () -> Void) { self.init(title: title, back: back) { EmptyView() } }
}

/// 쌓인 무료 카드·무료 팩 한 줄.
private struct FreeRow: View {
    let systemImage: String
    let title: String
    let hint: String
    let button: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage).font(.title2).foregroundStyle(.tint).frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.medium)).monospacedDigit()
                Text(hint).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 4)
            Button(button, action: action)
                .buttonStyle(.glassProminent)
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
    /// 패널 안 화면이 아니라 새 창으로 열리면 꺾쇠 대신 창 아이콘
    var opensWindow = false
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
                if opensWindow { Image(systemName: "arrow.up.right.square").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)}
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

/// 마우스를 올리면 말풍선으로 설명을 띄운다.
// ponytail: 메뉴바 패널(.window)에서는 .help 툴팁이 뜨지 않아 hover + popover 로 대신한다. 일반 창(컬렉션)은 .help 그대로.
private struct HoverHint: ViewModifier {
    let text: String
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .onHover { shown = $0 }
            .popover(isPresented: $shown, arrowEdge: .top) {
                Text(text).font(.callout).padding(10).fixedSize()
                    .presentationBackground(.thickMaterial)  // 기본 유리보다 덜 비치게
            }
    }
}

extension View {
    func hoverHint(_ text: String) -> some View { modifier(HoverHint(text: text)) }

    /// 패널 안 스크롤의 아래 끝. 살짝 흐려지며(재질 띠) 투명해져서 글자가 반 토막으로 잘려 보이지 않는다.
    /// 끝까지 내리면 마지막 줄이 띠 위에 오도록 내용 아래에 띠 높이만큼 여백을 둔다.
    func panelScrollBottom(_ height: CGFloat = 16) -> some View {
        let fade = LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
        return contentMargins(.bottom, height, for: .scrollContent)
            .overlay(alignment: .bottom) {
                Rectangle().fill(.ultraThinMaterial)
                    .mask(LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom))
                    .frame(height: height)
                    .allowsHitTesting(false)
            }
            .mask { VStack(spacing: 0) { Color.black; fade.frame(height: height) } }
    }
}

/// 코인 표기: ⓒ 1,000
/// 만 단위부터 K·M (12,345 → 12.3K, 1,000,000 → 1M). 메뉴바와 `coinText`가 같이 쓴다
func shortCoins(_ n: Int) -> String {
    guard abs(n) >= 10_000 else { return n.formatted() }
    return n.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)).locale(Locale(identifier: "en_US")))
}

func coinText(_ n: Int) -> String { "ⓒ \(shortCoins(n))" }

/// 1,000 미만은 그대로 (0.5K 를 "0K" 로 보이지 않게)
func shortTokens(_ n: Int) -> String {
    n < 1_000 ? "\(n)" : n >= 1_000_000 ? String(format: "%.1fM", Double(n) / 1e6) : String(format: "%.0fK", Double(n) / 1e3)
}
