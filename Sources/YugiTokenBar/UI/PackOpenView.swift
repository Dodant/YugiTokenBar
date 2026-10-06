import SwiftUI

/// 팝오버 안 팩·무료 카드 개봉 화면. 상점처럼 요약 화면 위에 겹쳐 그린다(패널 높이 고정).
struct OpeningView: View {
    @EnvironmentObject var model: AppModel
    @State private var flipped: Set<Int> = []
    @State private var width: CGFloat = 300

    var body: some View {
        let pulls = model.opening
        let allFlipped = flipped.count == pulls.count
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                Button { model.showOpening = false } label: {
                    Image(systemName: "chevron.left").font(.body.weight(.semibold)).frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .keyboardShortcut(.cancelAction)
                Text(model.openingTitle).font(.title3.weight(.semibold)).lineLimit(1)
                Spacer()
            }
            // 팩은 위 4장 + 레어 1장(3열 칸의 1.75배, 패널이 낮으면 남은 높이에 맞춰 줄어든다. 위 줄과 아래 버튼 사이 세로 가운데). 무료 카드는 3열, 1~2장이면 그 수만큼 열을 줘서 폭을 채운다
            let packLayout = model.openingPack != nil && pulls.count == 5
            let cols = packLayout ? 4 : min(max(pulls.count, 1), 3)
            let cellW = (width - 10 * CGFloat(cols - 1)) / CGFloat(cols)
            let rareW = (width - 20) / 3 * 1.75
            VStack(spacing: 10) {
                ForEach(Array(stride(from: 0, to: pulls.count, by: cols)), id: \.self) { start in
                    HStack(alignment: .bottom, spacing: 10) {
                        ForEach(start..<min(start + cols, pulls.count), id: \.self) { i in
                            cell(pulls[i], i).frame(width: isRare(i) ? nil : cellW).frame(maxWidth: isRare(i) ? rareW : nil)
                        }
                    }
                    .frame(maxHeight: isRare(start) ? .infinity : nil)
                }
            }
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            if !packLayout { Spacer(minLength: 0) }
            HStack(spacing: 8) {
                if allFlipped, let again {
                    Button("확인") { model.showOpening = false }.buttonStyle(.glass)
                    Button(again.title, action: again.action)
                        .disabled(!again.enabled)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(allFlipped ? "확인" : "모두 뒤집기") {
                        if allFlipped { model.showOpening = false }
                        else { flipAll(pulls) }
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
        }
        .onChange(of: model.openingID) { flipped = [] }
    }

    /// 팩의 마지막 칸은 R 이상 확정 레어 슬롯이라 조금 크게 둔다
    private func isRare(_ i: Int) -> Bool { model.openingPack != nil && i == model.opening.count - 1 }

    private func cell(_ pull: Pull, _ i: Int) -> some View {
        VStack(spacing: 4) {
            FlipCard(pull: pull, db: model.db, flipped: flipped.contains(i), canUnsell: model.game.state.coins >= (pull.soldFor ?? 0)) { model.keepSold(at: i) }
                .onTapGesture { withAnimation(.easeInOut(duration: 0.4)) { _ = flipped.insert(i) } }
            // 상점 팩 칸처럼 아래 이름 한 줄. 뒤집기 전엔 자리만 잡아 둔다(줄 높이 고정)
            Text(model.db.cards[pull.cid]?.name ?? " ")
                .font(.caption2).lineLimit(1).truncationMode(.tail)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .opacity(flipped.contains(i) ? 1 : 0)
        }
    }

    /// 레어 슬롯은 나머지를 먼저 뒤집고 0.6초 뒤에 뒤집는다
    private func flipAll(_ pulls: [Pull]) {
        let rare = pulls.indices.last.flatMap { isRare($0) && !flipped.contains($0) ? $0 : nil }
        withAnimation(.easeInOut(duration: 0.4)) { flipped.formUnion(pulls.indices.filter { $0 != rare }) }
        guard let rare else { return }
        let id = model.openingID
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard model.openingID == id else { return }
            withAnimation(.easeInOut(duration: 0.4)) { _ = flipped.insert(rare) }
        }
    }

    /// 다 뒤집은 뒤 한 번 더: 팩(무료 팩 포함)이면 같은 팩을 코인으로, 무료 카드면 남은 장을. 둘 다 아니면 nil.
    private var again: (title: String, enabled: Bool, action: () -> Void)? {
        if let pack = model.openingPack {
            return ("한 팩 더 · \(coinText(Balance.packPrice))", model.game.canBuy(pack), { model.buy(pack: pack) })
        }
        let left = model.game.state.pendingFree
        return left > 0 ? ("다음 \(min(left, Balance.freeOpenBatch))장 열기", true, { model.openFree() }) : nil
    }
}

struct FlipCard: View {
    let pull: Pull
    let db: CardDB
    let flipped: Bool
    var canUnsell = false
    /// 자동 판매 표시(+ⓒ)에 마우스를 올리면 ✕ 로 바뀌고, 누르면 판매를 취소한다
    var onUnsell: (() -> Void)?
    @State private var hoverSold = false

    var body: some View {
        ZStack {
            CardImageView(db: db, cid: pull.cid, size: .full)
                .overlay(alignment: .bottomLeading) { RarityPill(label: pull.label, size: 10).padding(4) }
                .overlay(alignment: .topTrailing) {
                    if pull.isNew { tag("NEW", .pink) }
                    else if let coins = pull.soldFor {
                        Button { onUnsell?() } label: {
                            tag(hoverSold && canUnsell ? "✕ 안 팔기" : "+\(coinText(coins))", hoverSold && canUnsell ? .red : .green)
                        }
                        .buttonStyle(.plain)
                        .disabled(!canUnsell)
                        .onHover { hoverSold = $0 }
                        .help(canUnsell ? "판매 취소: 코인을 돌려주고 카드를 가져요" : "코인이 모자라 취소할 수 없어요")
                    }
                }
                .shadow(color: pull.tier == 2 ? Rarity.color(tier: 2) : .clear, radius: 10)
                .modifier(RareEffect(tier: pull.tier, active: flipped))
                .rotation3DEffect(.degrees(flipped ? 0 : -180), axis: (x: 0, y: 1, z: 0))
                .opacity(flipped ? 1 : 0)
            CardBack(glow: pull.tier >= 2 ? Rarity.color(tier: pull.tier) : nil)
                .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
                .opacity(flipped ? 0 : 1)
        }
        .cardTilt(tier: pull.tier, enabled: flipped)  // 뒤집기 회전 바깥에서 기운다
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color, in: Capsule())
            .padding(4)
    }
}

/// SR·UR 앞면이 드러날 때의 연출 (뒤집기 0.4초가 끝날 즈음 시작).
/// SR: 금빛 광택 한 번 + 빛 맥박 + 살짝 튀어오름. UR: 무지개 광택 반복 + 빛 고리·반짝이 폭발 + 크게 튀어오름.
/// SE: UR 연출에 고리·반짝이를 더하고 더 크게 튀어오름.
private struct RareEffect: ViewModifier {
    let tier: Int
    let active: Bool
    @State private var sweep = false
    @State private var burst = false
    @State private var pulse = false
    @State private var pop = 0

    private var ur: Bool { tier >= 4 }
    private var se: Bool { tier >= 5 }

    func body(content: Content) -> some View {
        if tier < 3 {
            content
        } else {
            let color = Rarity.color(tier: tier)
            content
                .overlay { shine.allowsHitTesting(false) }
                .shadow(color: color.opacity(pulse ? 0.95 : 0.45), radius: pulse ? 20 : 9)
                .shadow(color: se ? Self.gold.opacity(pulse ? 0.9 : 0.3) : .clear, radius: pulse ? 28 : 12)
                .background { if ur { rings(color) } }
                .overlay { if ur { sparkles(color) } }
                .keyframeAnimator(initialValue: 1.0, trigger: pop) { view, scale in
                    view.scaleEffect(scale)
                } keyframes: { _ in
                    LinearKeyframe(1.0, duration: 0.3)
                    SpringKeyframe(se ? 1.2 : ur ? 1.14 : 1.06, duration: 0.18)
                    SpringKeyframe(1.0, duration: 0.4, spring: .bouncy)
                }
                .onChange(of: active) { start() }
                .onAppear { start() }
        }
    }

    private static let gold = Color(red: 1, green: 0.8, blue: 0.25)

    /// SE 는 금색 빛줄기 두 줄이 잇따라 지나간다
    private var shine: some View {
        GeometryReader { g in
            ForEach(0..<(se ? 2 : 1), id: \.self) { i in
                LinearGradient(colors: se
                               ? [.clear, .orange.opacity(0.5), Self.gold.opacity(0.95), .white, Self.gold.opacity(0.95), .orange.opacity(0.5), .clear]
                               : ur
                               ? [.clear, .pink.opacity(0.45), .white.opacity(0.85), .cyan.opacity(0.45), .clear]
                               : [.clear, .white.opacity(0.75), .clear],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: g.size.width * (i == 0 ? 0.7 : 0.35), height: g.size.height * 1.6)
                    .rotationEffect(.degrees(20))
                    .offset(x: (sweep ? g.size.width * 1.3 : -g.size.width * 1.0) - Double(i) * g.size.width * 0.9,
                            y: -g.size.height * 0.3)
                    .blendMode(.plusLighter)
            }
        }
        .clipShape(.rect(cornerRadius: 7))
    }

    private func rings(_ color: Color) -> some View {
        ZStack {
            ForEach(0..<(se ? 3 : 2), id: \.self) { i in
                Circle()
                    .stroke(color, lineWidth: 3)
                    .scaleEffect(burst ? 1.8 + Double(i) * 0.6 : 0.3)
                    .opacity(burst ? 0 : 0.9)
            }
        }
    }

    private func sparkles(_ color: Color) -> some View {
        ZStack {
            let n = se ? 16 : 10
            ForEach(0..<n, id: \.self) { i in
                let angle = Double(i) / Double(n) * 2 * .pi
                let r = burst ? 70.0 + Double(i % 3) * 14 : 0
                Image(systemName: "sparkle")
                    .font(.system(size: CGFloat(10 + (i % 3) * 4), weight: .bold))
                    .foregroundStyle(i.isMultiple(of: 2) ? color : se && i % 4 == 1 ? Self.gold : .white)
                    .offset(x: cos(angle) * r, y: sin(angle) * r)
                    .scaleEffect(burst ? 1 : 0.2)
                    .opacity(burst ? 0 : 1)
            }
        }
        .allowsHitTesting(false)
    }

    private func start() {
        guard active else {
            // 다음 팩: 애니메이션 없이 처음 상태로
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { sweep = false; burst = false; pulse = false }
            return
        }
        pop += 1
        withAnimation(ur
                      ? .easeInOut(duration: se ? 1.6 : 1.4).delay(0.35).repeatForever(autoreverses: false)
                      : .easeInOut(duration: 0.9).delay(0.35)) { sweep = true }
        withAnimation(.easeOut(duration: 0.9).delay(0.35)) { burst = true }
        withAnimation(.easeInOut(duration: 1.1).delay(0.35).repeatForever()) { pulse = true }
    }
}
