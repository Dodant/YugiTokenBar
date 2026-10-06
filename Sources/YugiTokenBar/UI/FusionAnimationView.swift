import SwiftUI

/// 융합 연출에 쓸 카드: 융합 결과와 소재(장 수만큼 반복)
struct FusionShow: Identifiable, Equatable {
    let cid: Int
    let materials: [Int]
    var id: Int { cid }
}

/// 컬렉션 창 위에 겹치는 융합 연출. 소재 카드가 둥둥 떠다니다(`float`초) 회오리로 섞이며 가운데로 빨려 들고(`swirl`초),
/// 번쩍인 뒤 융합 카드가 튀어나온다(팩 개봉과 같은 `RareEffect`). 아무 데나 누르면 닫힌다(도중이면 건너뛴다).
/// 시간 t 하나로 모든 위치를 계산해서 상태가 없다.
struct FusionAnimationView: View {
    let db: CardDB
    let show: FusionShow
    let onDone: () -> Void
    @State private var start = Date.now

    private static let float = 1.4, swirl = 1.4, reveal = float + swirl
    private static let gold = Color(red: 1, green: 0.8, blue: 0.25)

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSince(start)
            let s = min(max((t - Self.float) / Self.swirl, 0), 1)  // 회오리 진행도
            ZStack {
                Color.black.opacity(0.65 * min(t / 0.3, 1))
                // 회오리 가운데에 모이는 빛
                Circle()
                    .fill(RadialGradient(colors: [.white, Self.gold.opacity(0.8), .clear], center: .center, startRadius: 0, endRadius: 90))
                    .frame(width: 180, height: 180)
                    .scaleEffect(0.3 + s * 1.2)
                    .opacity(t < Self.reveal ? s : max(0, 1 - (t - Self.reveal) / 0.6))
                    .blendMode(.plusLighter)
                ForEach(Array(show.materials.enumerated()), id: \.offset) { i, cid in
                    material(cid, i, t, s)
                }
                if t >= Self.reveal { result(t - Self.reveal) }
                Color.white.opacity(max(0, 1 - abs(t - Self.reveal) / 0.25)).blendMode(.plusLighter)
            }
            .ignoresSafeArea()
        }
        .contentShape(.rect)
        .onTapGesture { onDone() }
    }

    /// 소재 한 장: 원 위에 고르게 놓여 천천히 돌며 흔들리다, 회오리에서 점점 빨리 돌며 반지름·크기가 줄고 사라진다
    private func material(_ cid: Int, _ i: Int, _ t: Double, _ s: Double) -> some View {
        let n = Double(show.materials.count)
        let angle = Double(i) / n * 2 * .pi - .pi / 2 + t * 0.25 + s * s * 6 * .pi
        let r = 170 * (1 - s * s)
        let bob = sin(t * 2.2 + Double(i) * 1.3) * 10 * (1 - s)
        let appear = min(max((t - Double(i) * 0.12) / 0.35, 0), 1)
        return CardImageView(db: db, cid: cid)
            .frame(width: 110)
            .shadow(color: Self.gold.opacity(0.6), radius: 10)
            .rotationEffect(.degrees(sin(t * 1.6 + Double(i)) * 7 * (1 - s) + s * s * 540))
            .scaleEffect(appear * (1 - 0.8 * s))
            .opacity(appear * (s < 0.75 ? 1 : 1 - (s - 0.75) / 0.25))
            .offset(x: cos(angle) * r, y: sin(angle) * r * 0.8 + bob)
    }

    /// 융합 카드: 작게 튀어나와 살짝 넘쳤다가 자리 잡는다(easeOutBack)
    private func result(_ dt: Double) -> some View {
        let p = min(dt / 0.5, 1) - 1
        let scale = 1 + 2.7 * p * p * p + 1.7 * p * p
        return VStack(spacing: 14) {
            CardImageView(db: db, cid: show.cid, size: .full)
                .frame(width: 190)
                .modifier(RareEffect(tier: max(db.tier(show.cid), 3), active: true))
                .scaleEffect(scale)
            Text(db.cards[show.cid]?.name ?? "")
                .font(.title2.bold())
                .foregroundStyle(.white)
                .opacity(min(dt / 0.6, 1))
            Text("눌러서 닫기")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6 * min(max(dt - 1, 0), 1)))
        }
    }
}
