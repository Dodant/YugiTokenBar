#if os(macOS)
import SwiftUI

struct PopoverView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.lessMotion) private var lessMotion
    /// 무료 팩·무료 카드 줄이 보이는지. 덮여 있는 동안(개봉·상점·설정)에는 새로 생기는 줄은 미뤘다가 돌아왔을 때 보이고
    /// (팩을 까다 무료 팩이 생겨도 개봉 화면이 늘어나지 않게), 다 써서 사라지는 줄은 바로 뺀다(마지막 무료 팩을 열면 원래 높이로)
    @State private var freeRows: (pack: Bool, card: Bool)?
    /// 바로 구매 줄에 보이는 팩 (스와이프로 넘김)
    @State private var shownPack: Int?
    @Environment(\.workMode) private var workMode
    /// 최근 획득 줄이 보이는지 (업무 모드면 없음). freeRows 처럼 덮인 동안(설정에서 업무 모드를 끔) 다시 생기는 건 돌아왔을 때로 미룬다
    @State private var showRecent: Bool?

    var body: some View {
        // ponytail: MenuBarExtra(.window) 패널은 내용 높이가 바뀌면 다시 그리지 못해 깨진다 → 상점·개봉·설정은 요약 크기 안에 겹쳐 그려 높이를 고정
        let covered = model.screen != .summary
        return summary
            .opacity(covered ? 0 : 1)
            .allowsHitTesting(!covered)
            .overlay {
                Group {
                    switch model.screen {
                    // 개봉마다 새 뷰로 만들어 뒤집기·레어 연출 상태를 처음부터 시작한다
                    case .opening: OpeningView().id(model.opening.id)
                    case .shop: ShopView()
                    case .settings: SettingsView(open: show)
                    case .usage: UsageDetailView()
                    case .summary: EmptyView()
                    }
                }
            }
            // 화면 전환은 바로 바꾼다: 페이드로 겹쳐 그리면 중간에 두 화면의 투명도 합이 1 아래로 처져 뒤 유리 패널이 하얗게 번쩍인다
            .padding(16)
            .frame(width: 340)
            .background { FieldBackground(imageId: model.fieldBackground.flatMap { model.game.db.cards[$0]?.imageId }) }
            .onChange(of: [covered, model.game.state.freePacks > 0, model.game.state.pendingFree > 0], initial: true) {
                let now = (pack: model.game.state.freePacks > 0, card: model.game.state.pendingFree > 0)
                freeRows = covered ? (now.pack && freeRows?.pack ?? false, now.card && freeRows?.card ?? false) : now
            }
            .onChange(of: [covered, workMode], initial: true) { showRecent = !workMode && (!covered || showRecent ?? true) }
    }

    // 패널 자체가 Liquid Glass 라서 내용에는 유리를 겹치지 않는다(겹치면 뒤 배경 색이 번져 탁해짐).
    private var summary: some View {
        let game = model.game
        let state = game.state
        let swipeScale = lessMotion ? 1 : 0.88
        return VStack(alignment: .leading, spacing: 16) {
            header(state)

            // ponytail: 덮인 화면(개봉·상점·설정) 중에 생기면 패널이 한 줄 늘어난다. 저장 실패는 드물어서 freeRows 처럼 미루지 않는다
            if let error = model.saveError {
                FreeRow(systemImage: "exclamationmark.triangle.fill", title: "진행 상황을 저장하지 못했어요",
                        hint: error, button: "폴더 열기") { NSWorkspace.shared.activateFileViewerSelecting([model.saveFolder]) }
                    .panelCard()
                    .tint(Palette.warning)
            }
            if let recovery = model.loadRecovery {
                FreeRow(systemImage: "exclamationmark.triangle.fill",
                        title: recovery == .backup ? "세이브가 손상되어 백업에서 복구했어요" : "세이브가 손상되어 새로 시작했어요",
                        hint: String(localized: "손상된 파일은 세이브 폴더에 남겨 두었어요."), button: "OK") { model.loadRecovery = nil }
                    .panelCard()
                    .tint(Palette.warning)
            }

            if showRecent ?? !workMode { VStack(alignment: .leading, spacing: 8) {
                caption("최근 획득")
                HStack(spacing: 9) {
                    ForEach(Array(state.log.prefix(5).enumerated()), id: \.offset) { _, entry in
                        CardImageView(db: game.db, cid: entry.cid, overframe: game.showsOverframe(entry.cid))
                            .frame(width: 54)
                            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                            .cardTilt(tier: game.db.tier(entry.cid), angleScale: 0.5)
                            .hoverHint(verbatim: game.db.cards[entry.cid]?.name ?? "")
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(game.db.cards[entry.cid]?.name ?? "")
                            .accessibilityAddTraits(.isImage)
                    }
                    if state.log.isEmpty {
                        // 처음엔 코인이 0이라 구매 버튼이 꺼져 있다 → 코인을 얻는 방법을 알려 준다
                        Text("토큰을 쓰면 코인이 쌓여요 · \(coinText(Balance.packPrice)) = 1팩").font(.callout).foregroundStyle(.secondary)
                    }
                }
                .frame(height: 79)
            } }

            // 무료 카드(위)·무료 팩(아래)은 둘 다 있으면 한 칸에 구분선으로 나눠 설명 없이 한 줄씩 둔다
            let showPack = freeRows?.pack ?? (state.freePacks > 0)
            let showCard = freeRows?.card ?? (state.pendingFree > 0)
            if showPack || showCard {
                let compact = showPack && showCard
                VStack(spacing: 8) {
                    if showCard {
                        FreeRow(systemImage: "gift.fill", title: "무료 카드 \(state.pendingFree)장", hint: String(localized: "토큰으로 모은 카드예요"),
                                button: state.pendingFree > Balance.freeOpenBatch ? "\(Balance.freeOpenBatch)장 열기" : "열기",
                                openAll: state.pendingFree > Balance.freeOpenAllMin ? { model.openFree(all: true) } : nil, compact: compact) { model.openFree() }
                    }
                    if showPack && showCard { Divider() }
                    if showPack {
                        FreeRow(systemImage: "shippingbox.fill", title: "무료 팩 \(state.freePacks)개",
                                hint: String(localized: "\(Balance.packsPerFreePack)팩마다 랜덤 부스터 1팩"), button: "열기",
                                openAll: state.freePacks > 1 ? { model.openAllFreePacks() } : nil, compact: compact) { model.openFreePack() }
                    }
                }
                .panelCard()
            }

            // 트랙패드 좌우 스와이프로 발매순 앞뒤 팩을 넘긴다. 사면 그 팩이 lastBoughtPack 이 되어 그대로 남는다
            // LazyHStack 가로 스크롤은 높이를 내용에서 못 받아 0이 되므로, 숨긴 한 줄로 높이를 잡는다
            PackRow(index: game.lastBoughtPack).padding(12).hidden()
                .overlay {
                    ScrollView(.horizontal) {
                        // ponytail: LazyHStack 은 안 그린 칸 폭을 어림해서 스냅 위치가 칸 사이에 걸렸다 → 전부 만들되 현재 팩 앞뒤 3칸만 내용을 채운다
                        HStack(spacing: 10) {
                            ForEach(game.db.packs.indices, id: \.self) { i in
                                Group {
                                    if abs(i - (shownPack ?? game.lastBoughtPack)) <= 3 { PackRow(index: i).padding(12) } else { Color.clear }
                                }
                                    .containerRelativeFrame(.horizontal)
                                    .background(workMode ? AnyShapeStyle(.fill.quinary)  // 업무 모드는 한 색으로 밋밋하게
                                                : AnyShapeStyle(LinearGradient(colors: Palette.packGlow(i), startPoint: .topLeading, endPoint: .bottomTrailing)),
                                                in: .rect(cornerRadius: 16))
                                    // 넘어가는 동안 살짝 작아지고 흐려졌다가 자리에 붙는다
                                    .scrollTransition { row, phase in
                                        row.scaleEffect(phase.isIdentity ? 1 : swipeScale)
                                            .opacity(phase.isIdentity ? 1 : 0.4)
                                    }
                            }
                        }
                        .scrollTargetLayout()
                    }
                    // 팩 사이 틈(spacing)까지 한 칸씩 붙도록 paging 대신 viewAligned
                    .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
                    .scrollIndicators(.never)
                    .scrollPosition(id: $shownPack)
                    // 한 팩 넘길 때마다 트랙패드에 톡 (Force Touch 트랙패드)
                    .sensoryFeedback(.alignment, trigger: shownPack)
                }
                .onChange(of: game.lastBoughtPack, initial: true) { shownPack = game.lastBoughtPack }
            .clipShape(.rect(cornerRadius: 16))

            VStack(spacing: 2) {
                MenuRow(title: "상점", systemImage: "bag", trailing: nil, chevron: true) { model.screen = .shop }
                MenuRow(title: "컬렉션", systemImage: "square.stack.3d.up",
                        trailing: "\(game.ownedDistinct) / \(game.db.allCIDs.count)", chevron: false, opensWindow: true) { show("dex") }
                Divider().padding(.horizontal, 10).padding(.vertical, 4)
                UsageView()
                Divider().padding(.horizontal, 10).padding(.vertical, 4)
                MenuRow(title: "설정", systemImage: "gearshape", trailing: nil, chevron: true) { model.screen = .settings }
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

    private func caption(_ text: LocalizedStringKey) -> some View {
        Text(text).font(.caption.weight(.medium)).foregroundStyle(.secondary)
    }

    private func show(_ id: String) { StatusMenu.show(id, openWindow) }
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
    let title: LocalizedStringKey
    /// 저장 오류 메시지(데이터)도 받으므로 String
    let hint: String
    let button: LocalizedStringKey
    /// 있으면 [All]를 뒤에 둔다
    var openAll: (() -> Void)?
    /// 무료 카드·팩이 한 칸에 같이 있을 때: 설명을 빼고 아이콘을 줄인다
    var compact = false
    let action: () -> Void

    var body: some View {
        HStack(spacing: compact ? 8 : 12) {
            // 강조색(파랑)은 유리 배경 위에서 잘 안 보여 글자색으로
            Image(systemName: systemImage).font(compact ? .title3 : .title2).foregroundStyle(.primary).symbolRenderingMode(.hierarchical).frame(width: compact ? 24 : 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.medium)).monospacedDigit()
                if !compact { Text(hint).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            }
            Spacer(minLength: 4)
            if let openAll {
                // 컨테이너 간격 0: 기본 간격이면 유리끼리 붙어 사이가 안 보인다. 줄이 좁아도 글자가 잘리지 않게 fixedSize
                GlassEffectContainer(spacing: 0) { HStack(spacing: 3) {
                    Button(button, action: action).buttonStyle(JoinedButtonStyle(side: .leading, prominent: true))
                    Button("All") { openAll() }.buttonStyle(JoinedButtonStyle(side: .trailing))
                } }
                .fixedSize()
            } else {
                Button(button, action: action)
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
            }
        }
    }
}

/// 붙여 놓은 두 유리 버튼의 한쪽 (한 캡슐을 둘로 나눈 모양): 바깥쪽만 둥글고 맞닿는 쪽은 직선
struct JoinedButtonStyle: ButtonStyle {
    let side: HorizontalEdge
    var prominent = false
    @Environment(\.controlSize) private var controlSize
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let height: CGFloat = controlSize == .large ? 28 : 24  // 시스템 유리 버튼 높이 (스크린샷으로 맞춤)
        let r = side == .leading ? (height / 2, 0.0) : (0.0, height / 2)
        let shape = UnevenRoundedRectangle(topLeadingRadius: r.0, bottomLeadingRadius: r.0, bottomTrailingRadius: r.1, topTrailingRadius: r.1)
        configuration.label
            .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, height / 2)
            .frame(height: height)
            .contentShape(shape)
            .glassEffect(prominent ? .regular.tint(.accentColor).interactive() : .regular.interactive(), in: shape)
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.5)
    }
}

/// 제어 센터·Wi-Fi 메뉴 같은 한 줄 버튼. 마우스를 올리면 배경이 생긴다.
private struct MenuRow: View {
    let title: LocalizedStringKey
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
                Image(systemName: systemImage).frame(width: 20).foregroundStyle(.secondary).symbolRenderingMode(.hierarchical)
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

private extension View {
    /// 팝오버 패널의 둥근 카드 배경.
    func panelCard() -> some View {
        padding(12).background(.fill.quinary, in: .rect(cornerRadius: 16))
    }
}

/// 설정 [필드 배경]: 고른 필드 마법 일러스트를 팝오버 전체에 은은하게 깐다 (업무 모드면 없음)
private struct FieldBackground: View {
    let imageId: Int?
    @Environment(\.workMode) private var workMode
    @State private var art: NSImage?

    var body: some View {
        Color.clear
            .overlay {
                if let art {
                    // opaque: 가장자리가 투명하게 번지지 않게
                    Image(nsImage: art).resizable().scaledToFill().blur(radius: 12, opaque: true).opacity(0.28)
                }
            }
            .clipped()
            .accessibilityHidden(true)
            .task(id: workMode ? nil : imageId) {
                art = nil
                guard !workMode, let imageId else { return }
                art = await ImageCache.shared.fieldArt(imageId)
            }
    }
}
#endif
