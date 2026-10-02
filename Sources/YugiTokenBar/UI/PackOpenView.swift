import SwiftUI

/// 팝오버 안 팩·무료 카드 개봉 화면. 상점처럼 요약 화면 위에 겹쳐 그린다(패널 높이 고정).
struct OpeningView: View {
    @EnvironmentObject var model: AppModel
    @State private var flipped: Set<Int> = []

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
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(Array(pulls.enumerated()), id: \.offset) { i, pull in
                    FlipCard(pull: pull, db: model.db, flipped: flipped.contains(i))
                        .onTapGesture { withAnimation(.easeInOut(duration: 0.4)) { _ = flipped.insert(i) } }
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                if allFlipped, let again {
                    Button("확인") { model.showOpening = false }.buttonStyle(.glass)
                    Button(again.title, action: again.action)
                        .disabled(!again.enabled)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(allFlipped ? "확인" : "모두 뒤집기") {
                        if allFlipped { model.showOpening = false }
                        else { withAnimation(.easeInOut(duration: 0.4)) { flipped = Set(pulls.indices) } }
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

    var body: some View {
        ZStack {
            CardImageView(db: db, cid: pull.cid, size: .full)
                .overlay(alignment: .bottomLeading) { RarityPill(label: pull.label, size: 10).padding(4) }
                .overlay(alignment: .topTrailing) {
                    if pull.isNew { tag("NEW", .pink) }
                    else if let coins = pull.soldFor { tag("+\(coinText(coins))", .green) }
                }
                .shadow(color: pull.tier == 2 ? Rarity.color(tier: 2) : .clear, radius: 10)
                .modifier(RareEffect(tier: pull.tier, active: flipped))
                .rotation3DEffect(.degrees(flipped ? 0 : -180), axis: (x: 0, y: 1, z: 0))
                .opacity(flipped ? 1 : 0)
            CardBack(glow: pull.tier >= 2 ? Rarity.color(tier: pull.tier) : nil)
                .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
                .opacity(flipped ? 0 : 1)
        }
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
private struct RareEffect: ViewModifier {
    let tier: Int
    let active: Bool
    @State private var sweep = false
    @State private var burst = false
    @State private var pulse = false
    @State private var pop = 0

    private var ur: Bool { tier >= 4 }

    func body(content: Content) -> some View {
        if tier < 3 {
            content
        } else {
            let color = Rarity.color(tier: tier)
            content
                .overlay { shine.allowsHitTesting(false) }
                .shadow(color: color.opacity(pulse ? 0.95 : 0.45), radius: pulse ? 20 : 9)
                .background { if ur { rings(color) } }
                .overlay { if ur { sparkles(color) } }
                .keyframeAnimator(initialValue: 1.0, trigger: pop) { view, scale in
                    view.scaleEffect(scale)
                } keyframes: { _ in
                    LinearKeyframe(1.0, duration: 0.3)
                    SpringKeyframe(ur ? 1.14 : 1.06, duration: 0.18)
                    SpringKeyframe(1.0, duration: 0.4, spring: .bouncy)
                }
                .onChange(of: active) { start() }
                .onAppear { start() }
        }
    }

    private var shine: some View {
        GeometryReader { g in
            LinearGradient(colors: ur
                           ? [.clear, .pink.opacity(0.45), .white.opacity(0.85), .cyan.opacity(0.45), .clear]
                           : [.clear, .white.opacity(0.75), .clear],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: g.size.width * 0.7, height: g.size.height * 1.6)
                .rotationEffect(.degrees(20))
                .offset(x: sweep ? g.size.width * 1.3 : -g.size.width * 1.0, y: -g.size.height * 0.3)
                .blendMode(.plusLighter)
        }
        .clipShape(.rect(cornerRadius: 7))
    }

    private func rings(_ color: Color) -> some View {
        ZStack {
            ForEach(0..<2, id: \.self) { i in
                Circle()
                    .stroke(color, lineWidth: 3)
                    .scaleEffect(burst ? 1.8 + Double(i) * 0.6 : 0.3)
                    .opacity(burst ? 0 : 0.9)
            }
        }
    }

    private func sparkles(_ color: Color) -> some View {
        ZStack {
            ForEach(0..<10, id: \.self) { i in
                let angle = Double(i) / 10 * 2 * .pi
                let r = burst ? 70.0 + Double(i % 3) * 14 : 0
                Image(systemName: "sparkle")
                    .font(.system(size: CGFloat(10 + (i % 3) * 4), weight: .bold))
                    .foregroundStyle(i.isMultiple(of: 2) ? color : .white)
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
                      ? .easeInOut(duration: 1.4).delay(0.35).repeatForever(autoreverses: false)
                      : .easeInOut(duration: 0.9).delay(0.35)) { sweep = true }
        withAnimation(.easeOut(duration: 0.9).delay(0.35)) { burst = true }
        withAnimation(.easeInOut(duration: 1.1).delay(0.35).repeatForever()) { pulse = true }
    }
}
