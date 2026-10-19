#if os(macOS)
import SwiftUI

/// 팝오버 안 팩·무료 카드 개봉 화면. 상점처럼 요약 화면 위에 겹쳐 그린다(패널 높이 고정).
struct OpeningView: View {
    @Environment(AppModel.self) private var model
    @State private var flipped: Set<Int> = []
    @State private var width: CGFloat = 300
    @Environment(\.lessMotion) private var lessMotion
    @Environment(\.workMode) private var workMode

    var body: some View {
        let pulls = model.opening.pulls
        let allFlipped = flipped.count == pulls.count
        VStack(spacing: 12) {
            PanelHeader(title: model.opening.title) { model.closeOpening() }
            // 팩은 위 4장 + 레어 1장(3열 칸의 1.75배, 패널이 낮으면 남은 높이에 맞춰 줄어든다. 위 줄과 아래 버튼 사이 세로 가운데). 무료 카드는 3열, 1~2장이면 그 수만큼 열을 줘서 폭을 채우고, 4장은 3열 크기로 2장씩 두 줄(6장은 3장씩 두 줄)
            let packLayout = model.opening.pack != nil && pulls.count == 5
            let cols = packLayout ? 4 : min(max(pulls.count, 1), 3)
            let perRow = !packLayout && pulls.count == 4 ? 2 : cols
            let cellW = (width - 10 * CGFloat(cols - 1)) / CGFloat(cols)
            let rareW = (width - 20) / 3 * 1.75
            if workMode {
                VStack(spacing: 6) {
                    ForEach(pulls.indices, id: \.self) { i in row(pulls[i], i) }
                }
                Spacer(minLength: 0)
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(stride(from: 0, to: pulls.count, by: perRow)), id: \.self) { start in
                        HStack(alignment: .bottom, spacing: 10) {
                            ForEach(start..<min(start + perRow, pulls.count), id: \.self) { i in
                                cell(pulls[i], i).frame(width: isRare(i) ? nil : cellW).frame(maxWidth: isRare(i) ? rareW : nil)
                            }
                        }
                        .frame(maxHeight: isRare(start) ? .infinity : nil)
                    }
                }
                .frame(maxWidth: .infinity)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
                if !packLayout { Spacer(minLength: 0) }
            }
            // 나란한 유리 버튼은 한 컨테이너에서 같이 그린다
            GlassEffectContainer { HStack(spacing: 8) {
                if allFlipped, let again {
                    Button("확인") { model.closeOpening() }.buttonStyle(.glass)
                    Button(again.title, action: again.action)
                        .disabled(!again.enabled)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(allFlipped ? "확인" : "모두 뒤집기") {
                        if allFlipped { model.closeOpening() }
                        else { flipAll(pulls) }
                    }
                    .keyboardShortcut(.defaultAction)
                }
            } }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
        }
    }

    /// 팩의 마지막 칸은 R 이상 확정 레어 슬롯이라 조금 크게 둔다
    private func isRare(_ i: Int) -> Bool { model.opening.pack != nil && i == model.opening.pulls.count - 1 }

    private func cell(_ pull: Pull, _ i: Int) -> some View {
        Hovering { hovered in VStack(spacing: 4) {
            flippable(FlipCard(pull: pull, db: model.db, overframe: pull.overframe, flipped: flipped.contains(i), canUnsell: model.game.state.coins >= (pull.soldFor ?? 0)) { model.keepSold(at: i) }, pull, i)
            // 상점 팩 칸처럼 아래 이름 한 줄(넘치면 마우스를 올린 동안 흘러간다). 뒤집기 전엔 자리만 잡아 둔다(줄 높이 고정)
            MarqueeText(text: model.db.cards[pull.cid]?.name ?? " ", active: hovered && flipped.contains(i))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .opacity(flipped.contains(i) ? 1 : 0)
                .accessibilityHidden(true)  // 위 카드가 이름을 읽는다 (뒤집기 전에 이름이 새지 않게)
        } }
    }

    /// 업무 모드 개봉 줄: 배지 칸(폭 고정, 오른쪽 정렬) · 종류 막대 · 등급 · 이름(아래 줄에 분류·레벨·공/수). 누르기 전엔 "눌러서 공개"만
    private func row(_ pull: Pull, _ i: Int) -> some View {
        let card = model.db.cards[pull.cid]
        return flippable(HStack(spacing: 8) {
            if flipped.contains(i) {
                // 배지가 없는 줄(새 카드도 판매도 아님)도 칸을 비워 둔다. PullBadge 가 비면 frame 이 사라져 이름이 왼쪽으로 당겨진다
                Color.clear.frame(width: Self.badgeWidth, height: 1)
                    .overlay(alignment: .trailing) {  // 등급 바로 옆에 붙인다
                        PullBadge(pull: pull, canUnsell: model.game.state.coins >= (pull.soldFor ?? 0)) { model.keepSold(at: i) }
                            .fixedSize()  // 마우스를 올린 "✕ 売らない"는 칸보다 넓어 왼쪽 여백으로 넘친다
                    }
                HStack(spacing: 5) {
                    FrameBar(card: card)
                    RarityPill(label: pull.label, size: 10, aligned: true)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Hovering { MarqueeText(text: card?.name ?? "", active: $0) }  // 넘치면 이름만 마우스를 올린 동안 흘러간다
                    Text(card?.workLine ?? "")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
                }
                Spacer(minLength: 0)
            } else {
                Text("눌러서 공개").foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.leading, 6)  // 줄 여백이 왼쪽 4·오른쪽 10 이라 맞춰 가운데에 둔다
            }
        }
        .font(.callout)
        .padding(.leading, 4)
        .padding(.trailing, 10)
        .frame(height: 42)
        .background(.fill.tertiary, in: .rect(cornerRadius: 6))
        .contentShape(.rect), pull, i)
    }

    /// 누르면(VoiceOver 동작도) 뒤집는 칸. 이름은 뒤집은 뒤에만 읽고, 자동 판매된 카드는 [판매 취소] 동작을 단다
    private func flippable(_ content: some View, _ pull: Pull, _ i: Int) -> some View {
        content
            .onTapGesture { flip(i) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel(pull, i))
            .accessibilityAddTraits(flipped.contains(i) ? [] : .isButton)
            .accessibilityAction { flip(i) }
            .accessibilityActions {
                if flipped.contains(i), pull.soldFor != nil { Button("판매 취소") { model.keepSold(at: i) } }
            }
    }

    private func flip(_ i: Int) { withAnimation(flip) { _ = flipped.insert(i) } }

    /// 배지 칸 폭: 평소 가장 넓은 "+ⓒ 1.2K" 52pt 가 들어간다 (마우스를 올린 "✕ 売らない" 58pt 는 왼쪽 여백 4pt 로 넘친다)
    private static let badgeWidth: CGFloat = 54

    /// 뒤집기 전 "카드 3, 뒤집기 전", 뒤집은 뒤 "푸른 눈의 백룡, UR, 새 카드" (자동 판매면 "+ⓒ 10 자동 판매")
    private func accessibilityLabel(_ pull: Pull, _ i: Int) -> String {
        guard flipped.contains(i) else { return String(localized: "카드 \(i + 1), 뒤집기 전") }
        var parts = [model.db.cards[pull.cid]?.name ?? "", pull.label]
        if pull.isNew { parts.append(String(localized: "새 카드")) }
        if pull.filledCards > 0 { parts.append(String(localized: "엑조디아! 팩을 모두 채웠어요")) }
        if pull.bonusPacks > 0 { parts.append(String(localized: "무료 팩 +\(pull.bonusPacks)")) }
        if let coins = pull.soldFor { parts.append(String(localized: "+\(coinText(coins)) 자동 판매")) }
        return parts.joined(separator: ", ")
    }

    private var flip: Animation? { lessMotion ? nil : .easeInOut(duration: 0.4) }

    /// 레어 슬롯은 나머지를 먼저 뒤집고 0.6초 뒤에 뒤집는다 (애니메이션을 끄면 한꺼번에)
    private func flipAll(_ pulls: [Pull]) {
        let rare = pulls.indices.last.flatMap { !lessMotion && isRare($0) && !flipped.contains($0) ? $0 : nil }
        withAnimation(flip) { flipped.formUnion(pulls.indices.filter { $0 != rare }) }
        guard let rare else { return }
        let id = model.opening.id
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard model.opening.id == id else { return }
            flip(rare)
        }
    }

    /// 다 뒤집은 뒤 한 번 더: 무료 팩이 남았으면 다음 무료 팩을, 팩이면 같은 팩을 코인으로, 무료 카드면 남은 장을. 모두 아니면 nil.
    private var again: (title: String, enabled: Bool, action: () -> Void)? {
        let freePacks = model.game.state.freePacks
        if model.opening.freePack && freePacks > 0 {
            return (String(localized: "다음 무료 팩 열기 · \(freePacks)개 남음"), true, { model.openFreePack() })
        }
        if let pack = model.opening.pack {
            return (String(localized: "한 팩 더 · \(coinText(Balance.packPrice))"), model.game.canAffordPack, { model.buy(pack: pack) })
        }
        let left = model.game.state.pendingFree
        return left > 0 ? (String(localized: "다음 \(min(left, Balance.freeOpenBatch))장 열기"), true, { model.openFree() }) : nil
    }
}

struct FlipCard: View {
    let pull: Pull
    let db: CardDB
    var overframe = false
    let flipped: Bool
    var canUnsell = false
    /// 배지의 판매 취소
    var onUnsell: (() -> Void)?
    @Environment(\.workMode) private var workMode

    var body: some View {
        ZStack {
            CardImageView(db: db, cid: pull.cid, size: .full, overframe: overframe)
                .overlay(alignment: .bottomLeading) { RarityPill(label: pull.label, size: 10).padding(4) }
                .overlay(alignment: .topTrailing) { PullBadge(pull: pull, canUnsell: canUnsell, onUnsell: onUnsell).padding(4) }
                .shadow(color: pull.tier == 2 && !workMode ? Rarity.color(tier: 2) : .clear, radius: 10)
                .modifier(RareEffect(tier: pull.tier, active: flipped))
                .rotation3DEffect(.degrees(flipped ? 0 : -180), axis: (x: 0, y: 1, z: 0))
                .opacity(flipped ? 1 : 0)
            CardBack(glow: pull.tier >= 2 ? Rarity.color(tier: pull.tier) : nil)
                .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
                .opacity(flipped ? 0 : 1)
        }
        .cardTilt(tier: pull.tier, enabled: flipped)  // 뒤집기 회전 바깥에서 기운다
    }
}

/// 개봉 카드의 엑조디아·무료 팩(욕망의 항아리)·NEW·자동 판매(+ⓒ) 배지. 판매 배지에 마우스를 올리면 ✕ 로 바뀌고, 누르면 판매를 취소한다
struct PullBadge: View {
    let pull: Pull
    var canUnsell = false
    var onUnsell: (() -> Void)?
    @State private var hoverSold = false

    var body: some View {
        if pull.filledCards > 0 { tag("엑조디아!", Palette.badgeGain) }
        else if pull.bonusPacks > 0 { tag("무료 팩 +\(pull.bonusPacks)", Palette.badgeGain) }
        else if pull.isNew { tag("NEW", Palette.badgeNew) }
        else if let coins = pull.soldFor {
            Button { onUnsell?() } label: {
                tag(hoverSold && canUnsell ? "✕ 안 팔기" : "+ⓒ \(shortCoins(coins, from: 1_000))", hoverSold && canUnsell ? Palette.badgeLoss : Palette.badgeGain)
            }
            .buttonStyle(.plain)
            .disabled(!canUnsell)
            .onHover { hoverSold = $0 }
            .help(canUnsell ? "판매 취소: 코인을 돌려주고 카드를 가져요" : "코인이 모자라 취소할 수 없어요")
        }
    }

    private func tag(_ text: LocalizedStringKey, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color, in: Capsule())
    }
}

/// SR·UR·SE 앞면이 드러날 때의 연출 (뒤집기 0.4초가 끝날 즈음 시작). 날리는 것 없이 빛만 절제해서 쓴다.
/// 공통: 옅은 섬광 + 대각선 광택 한 번(좌상단 → 우하단) + 부드럽게 떠올랐다 내려앉음 + 느린 빛 숨쉬기 + 카드 둘레에서 차례로 반짝이는 빛 점.
/// UR: 광택 띠 가장자리에 옅은 무지개 + 무지개 홀로 포일이 천천히 돈다 + 카드 모양 빛 테두리가 퍼진다.
/// SE: UR 에 금빛 광택·금빛 포일·금빛 후광·테두리 두 겹.
private struct RareEffect: ViewModifier {
    let tier: Int
    let active: Bool
    @State private var turn = false
    @State private var pulse = false
    @State private var pop = 0
    @Environment(\.lessMotion) private var lessMotion
    @Environment(\.workMode) private var workMode

    private var ur: Bool { tier >= 4 }
    private var se: Bool { tier >= 5 }
    nonisolated private static let corner = 7.0

    /// 한 번만 재생하는 등장 값 (끝값은 처음과 같은 '보이지 않음')
    private struct Reveal {
        var scale = 1.0, flash = 0.0, ring = 0.0, glint = 0.0, sweep = 0.0
    }

    func body(content: Content) -> some View {
        if tier < 3 || workMode {  // 업무 모드면 연출 없음
            content
        } else if lessMotion {
            content.shadow(color: Rarity.color(tier: tier).opacity(active ? 0.7 : 0), radius: 12)  // 연출 없이 빛만
        } else {
            let color = Rarity.color(tier: tier), ur = ur, se = se
            content
                .overlay { if ur { foil.allowsHitTesting(false) } }
                .shadow(color: color.opacity(pulse ? 0.8 : 0.4), radius: pulse ? 16 : 9)
                .shadow(color: se ? Rarity.gold.opacity(pulse ? 0.7 : 0.25) : .clear, radius: pulse ? 24 : 12)
                .keyframeAnimator(initialValue: Reveal(), trigger: pop) { view, v in
                    view
                        .overlay {
                            RoundedRectangle(cornerRadius: Self.corner).fill(.white)
                                .opacity(v.flash).blendMode(.plusLighter).allowsHitTesting(false)
                        }
                        .overlay { Self.sweep(v.sweep, ur: ur, se: se).allowsHitTesting(false) }
                        .background { if ur { Self.rings(color, v.ring, se: se) } }
                        .overlay { Self.glints(color, v.glint, n: se ? 6 : ur ? 4 : 2, se: se) }
                        .scaleEffect(v.scale)
                } keyframes: { _ in
                    KeyframeTrack(\.scale) {
                        LinearKeyframe(1, duration: 0.3)
                        CubicKeyframe(se ? 1.09 : ur ? 1.06 : 1.035, duration: 0.22)
                        SpringKeyframe(1, duration: 0.8, spring: .smooth)
                    }
                    KeyframeTrack(\.flash) {
                        LinearKeyframe(0, duration: 0.32)
                        LinearKeyframe(se ? 0.35 : ur ? 0.28 : 0.2, duration: 0.07)  // 광택 띠가 주인공이라 옅게
                        CubicKeyframe(0, duration: 0.6)
                    }
                    KeyframeTrack(\.ring) {
                        LinearKeyframe(0, duration: 0.34)
                        CubicKeyframe(1, duration: 1.1)
                    }
                    KeyframeTrack(\.sweep) {
                        LinearKeyframe(0, duration: 0.4)
                        LinearKeyframe(1, duration: se ? 1.9 : ur ? 1.7 : 1.5, timingCurve: .easeInOut)
                        MoveKeyframe(0)
                    }
                    KeyframeTrack(\.glint) {
                        LinearKeyframe(0, duration: 0.45)
                        LinearKeyframe(1, duration: 1.6)
                    }
                }
                .onChange(of: active) { start() }
                .onAppear { start() }
        }
    }

    /// 대각선 광택 한 번: 좌상단 모서리에서 맺힌 반사광 띠가 우하단으로 미끄러져 빠져나간다 (p: 0…1).
    /// 가운데가 밝고 양옆으로 번지는 띠 + 더 넓고 옅은 광채. 가운데쯤에서 가장 밝고 넓어지며 각도가 조금 돌아
    /// 곡면 위를 굴러가듯 보인다. UR 은 띠 가장자리에 옅은 무지개, SE 는 따뜻한 금빛.
    nonisolated private static func sweep(_ p: Double, ur: Bool, se: Bool) -> some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height, d = hypot(w, h)
            let theta = atan2(h, w)
            let bulge = sin(.pi * p)                      // 가운데서 1, 양끝 모서리에서 0
            let band = w * (0.32 + 0.16 * bulge)
            let s = (p - 0.5) * (d + band)                // 띠 가운데가 좌상단 모서리 → 우하단 모서리 밖
            let tint: Color = se ? Color(red: 1, green: 0.9, blue: 0.7) : .white
            let edge: (Color, Color) = ur && !se ? (.cyan, .pink) : (tint, tint)
            ZStack {
                // 주변 광채
                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: tint.opacity(0.14), location: 0.5),
                                       .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing)
                    .frame(width: band * 2.6)
                // 반사광 띠
                LinearGradient(stops: [.init(color: .clear, location: 0),
                                       .init(color: edge.0.opacity(0.12), location: 0.22),
                                       .init(color: tint.opacity(0.35), location: 0.4),
                                       .init(color: .white.opacity(0.62), location: 0.5),
                                       .init(color: tint.opacity(0.35), location: 0.6),
                                       .init(color: edge.1.opacity(0.12), location: 0.78),
                                       .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing)
                    .frame(width: band)
            }
            .frame(height: d * 1.4)
            .rotationEffect(.radians(theta + (p - 0.5) * 0.18))
            .position(x: w / 2 + cos(theta) * s, y: h / 2 + sin(theta) * s)
            .opacity(p > 0 && p < 1 ? pow(bulge, 0.5) : 0)
            .blendMode(.plusLighter)
        }
        .clipShape(.rect(cornerRadius: corner))
    }

    /// 홀로 포일: 무지개(SE 는 금·장미빛) 각도 그라데이션이 아주 옅게 천천히 돈다
    private var foil: some View {
        GeometryReader { g in
            let d = hypot(g.size.width, g.size.height)
            AngularGradient(colors: se
                            ? [Rarity.gold, .orange, .pink, .white, Rarity.gold]
                            : [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .red],
                            center: .center)
                .frame(width: d, height: d)
                .rotationEffect(.degrees(turn ? 360 : 0))
                .position(x: g.size.width / 2, y: g.size.height / 2)
                .opacity(0.1)
                .blendMode(.plusLighter)
        }
        .clipShape(.rect(cornerRadius: Self.corner))
    }

    /// 카드 모양 빛 테두리가 가늘어지며 퍼진다 (SE 는 금빛 한 겹이 뒤따른다)
    nonisolated private static func rings(_ color: Color, _ r: Double, se: Bool) -> some View {
        ZStack {
            ForEach(0..<(se ? 2 : 1), id: \.self) { i in
                let q = min(max((r - Double(i) * 0.18) / (1 - Double(i) * 0.18), 0), 1)
                RoundedRectangle(cornerRadius: Self.corner)
                    .stroke(i == 0 ? color : Rarity.gold, lineWidth: 2.5 * (1 - q) + 0.5)
                    .blur(radius: 1.5)
                    .scaleEffect(1 + 0.3 * q)
                    .opacity(q > 0 ? (1 - q) * 0.9 : 0)
            }
        }
    }

    /// 카드 둘레 정해진 자리에서 빛 점이 하나씩 피었다 진다
    nonisolated private static func glints(_ color: Color, _ g: Double, n: Int, se: Bool) -> some View {
        let spots: [UnitPoint] = [.init(x: 0.1, y: 0.06), .init(x: 0.9, y: 0.82), .init(x: 0.94, y: 0.2),
                                  .init(x: 0.08, y: 0.7), .init(x: 0.55, y: 0.02), .init(x: 0.45, y: 0.97)]
        return GeometryReader { geo in
            ForEach(0..<n, id: \.self) { i in
                let local = min(max((g - Double(i) / Double(n) * 0.5) / 0.5, 0), 1)
                let s = sin(.pi * local)
                Image(systemName: "sparkle")
                    .font(.system(size: CGFloat(i.isMultiple(of: 2) ? 15 : 11), weight: .light))
                    .foregroundStyle(.white)
                    .shadow(color: se && i % 2 == 1 ? Rarity.gold : color, radius: 4)
                    .scaleEffect(0.3 + 0.9 * s)
                    .rotationEffect(.degrees(60 * local))
                    .opacity(s)
                    .position(x: spots[i].x * geo.size.width, y: spots[i].y * geo.size.height)
            }
        }
        .allowsHitTesting(false)
    }

    private func start() {
        guard active else { return }  // 다음 팩은 개봉 화면째 새로 만들어져 처음 상태로 시작한다
        pop += 1
        if ur { withAnimation(.linear(duration: 10).delay(0.35).repeatForever(autoreverses: false)) { turn = true } }
        withAnimation(.easeInOut(duration: 2.2).delay(0.35).repeatForever()) { pulse = true }
    }
}
#endif
