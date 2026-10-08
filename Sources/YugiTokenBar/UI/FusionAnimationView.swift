import SwiftUI

/// 융합 연출에 쓸 카드: 융합 결과와 소재(장 수만큼 반복)
struct FusionShow: Identifiable, Equatable {
    let cid: Int
    let materials: [Int]
    var id: Int { cid }
}

/// 컬렉션 창 위에 겹치는 우주 느낌의 융합 연출. 도중에 누르면 융합 카드가 다 나온 장면으로 건너뛰고, 그다음 누르면 닫힌다.
/// 떠오름(0–3초): 성운·별 배경 위로 소재 카드가 떠다니고 뒤에서 은하 소용돌이가 생긴다.
/// 회오리(3–4.4초): 소용돌이가 빨라지고 카드가 뒤집히며 잔상을 남기고 빨려 든다. 별 알갱이도 같이 빨려 든다.
/// 폭발(4.6초): 가운데 빛이 오그라들었다 번쩍이고, 빛 고리·별 파편이 퍼진다.
/// 등장: 돌아가는 빛살 속에서 융합 카드가 솟아올라 두 바퀴 돌고, 광택·반짝임(UR 이상은 홀로그램)이 이어진다.
/// 시간 t 하나로 모든 것을 계산한다. 빛 효과는 흐린 겹과 선명한 겹을 더해 번지게 그린다.
struct FusionAnimationView: View {
    let db: CardDB
    let show: FusionShow
    let onDone: () -> Void
    @Environment(\.lessMotion) private var reduceMotion
    @State private var start = Date.now
    @State private var images: [Int: NSImage] = [:]

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let t = reduceMotion ? FusionScene.reveal + 2 : timeline.date.timeIntervalSince(start)
            Canvas { gc, size in
                FusionScene(t: t, size: size, materials: show.materials, result: show.cid,
                            tier: min(max(db.tier(show.cid), 3), 5), name: db.cards[show.cid]?.name ?? "", images: images)
                    .draw(gc)
            } symbols: {
                ForEach(FusionScene.palette.indices, id: \.self) { i in
                    let c = FusionScene.palette[i]
                    RadialGradient(stops: [.init(color: c, location: 0), .init(color: c.opacity(0.45), location: 0.2),
                                           .init(color: c.opacity(0.12), location: 0.5), .init(color: c.opacity(0), location: 1)],
                                   center: .center, startRadius: 0, endRadius: 32)
                        .frame(width: 64, height: 64)
                        .tag(i)
                }
                CardBack().frame(width: 118, height: 172).tag(-1)
            }
        }
        .ignoresSafeArea()
        .contentShape(.rect)
        .onTapGesture {
            let t = Date.now.timeIntervalSince(start)
            if reduceMotion || t >= FusionScene.done { onDone() } else { start = .now.addingTimeInterval(-FusionScene.done) }
        }
        .accessibilityElement()
        .accessibilityLabel("\(db.cards[show.cid]?.name ?? "") 융합. 누르면 건너뛰고, 한 번 더 누르면 닫기")
        .accessibilityAddTraits(.isButton)
        .task {
            for cid in Set(show.materials + [show.cid]) {
                guard let id = db.cards[cid]?.imageId else { continue }
                images[cid] = await ImageCache.shared.image(id, size: cid == show.cid ? .full : .small)
            }
        }
    }
}

private struct FusionScene {
    static let float = 3.0, swirl = 4.4, reveal = 4.6
    /// 카드가 다 돌고 섬광이 걷혀 이름이 뜬 때. 도중에 누르면 여기로 건너뛴다
    static let done = reveal + 1.2

    /// 빛 점 색 (Canvas 심볼 번호와 같다)
    enum P: Int { case purple, orange, gold, blue, pink, white }
    static let palette: [Color] = [
        Color(red: 0.59, green: 0.35, blue: 1), Color(red: 1, green: 0.59, blue: 0.24), Rarity.gold,
        Color(red: 0.31, green: 0.55, blue: 1), Color(red: 1, green: 0.35, blue: 0.78), .white,
    ]

    let t: Double
    let size: CGSize
    let materials: [Int]
    let result: Int
    let tier: Int
    let name: String
    let images: [Int: NSImage]

    /// 등급 색 두 가지 (광택 가장자리·반짝임·빛무리)
    private var tierColors: (Color, Color) {
        switch tier {
        case 5: (Rarity.gold, Color(red: 1, green: 0.6, blue: 0.24))
        case 4: (Color(red: 1, green: 0.42, blue: 0.84), Color(red: 0.42, green: 0.89, blue: 1))
        default: (Color(red: 1, green: 0.83, blue: 0.3), .white)
        }
    }

    func draw(_ root: GraphicsContext) {
        var gc = root
        let W = size.width, H = size.height
        let dt = t - Self.reveal
        let s = progress(at: t)
        gc.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(0.85 * clamp(t / 0.3))))
        let R = min(W * 0.33, H * 0.36, 200)
        let cw = clamp(R * 0.6, 64, 112)
        // 화면 흔들림: 회오리 끝 무렵과 폭발 순간
        let amp = (s > 0.6 && dt < 0 ? (s - 0.6) / 0.4 * 5 : 0) + (dt >= 0 ? 14 * max(0, 1 - dt / 0.45) : 0)
        gc.translateBy(x: W / 2 + sin(t * 93) * amp, y: H / 2 + cos(t * 71) * amp)

        cosmos(gc, W, H, dt)
        bloom(gc, 12) { g in
            galaxy(g, R, s, dt)
            if dt < 0 {
                stream(g, R, s)
                for i in materials.indices where s > 0 {  // 잔상
                    for k in stride(from: 4, through: 1, by: -1) {
                        let p = mat(i, t - Double(k) * 0.035, R)
                        card(g, nil, p, w: cw, alpha: p.alpha * 0.3 * (1 - Double(k) / 5) * min(s * 3, 1), whiten: 1)
                    }
                }
            }
        }
        if dt < 0 {
            for (i, cid) in materials.enumerated() {
                let p = mat(i, t, R)
                let pulse = 0.5 + 0.5 * sin(t * 4 + Double(i))
                let glowColor = p.s > 0.3 ? Color(red: 1, green: 0.95, blue: 0.75) : Self.palette[i % 2 == 1 ? 1 : 0]
                card(gc, cid, p, w: cw, alpha: p.alpha, whiten: p.whiten, glow: 14 + 14 * pulse + 30 * p.s, glowColor: glowColor)
            }
        } else {
            bloom(gc, 16) { g in burst(g, W, H, dt) }
            reveal(gc, W, H, dt)
        }
        // 섬광: 폭발 순간 화면이 하얗게
        let fl = dt < 0 ? max(0, 1 + dt / 0.12) * 0.6 : max(0, 1 - dt / 0.35)
        if fl > 0 {
            var f = gc
            f.blendMode = .plusLighter
            f.fill(Path(CGRect(x: -W, y: -H, width: W * 2, height: H * 2)), with: .color(Color(red: 1, green: 0.98, blue: 0.92).opacity(fl)))
        }
    }

    // MARK: 장면

    /// 우주 배경: 천천히 떠도는 성운과 반짝이는 별. 회오리 때 별도 조금 끌려 든다
    private func cosmos(_ gc: GraphicsContext, _ W: Double, _ H: Double, _ dt: Double) {
        var g = gc
        g.blendMode = .plusLighter
        let fadeIn = clamp(t / 0.8)
        let s = progress(at: t)
        let pull = s * s * (dt < 0 ? 1 : max(0, 1 - dt / 0.6))
        let nebulae: [(P, Double, Double)] = [(.purple, -0.35, -0.2), (.blue, 0.4, 0.25), (.pink, 0.1, -0.4), (.blue, -0.3, 0.35)]
        for (k, (p, nx, ny)) in nebulae.enumerated() {
            let x = nx * W + sin(t * 0.15 + Double(k) * 2) * 30
            let y = ny * H + cos(t * 0.12 + Double(k)) * 20
            puff(g, x, y, max(W, H) * (0.9 + (0.2 * Double(k)).truncatingRemainder(dividingBy: 0.5)), p, 0.22 * fadeIn)
        }
        let reach = (W * W + H * H).squareRoot() * 0.55
        for i in 0..<240 {
            let a = rnd(i, 20) * 2 * .pi + t * 0.02 + pull * 1.2 * (1 - rnd(i, 21) * 0.5)
            let r = (0.15 + rnd(i, 21) * 0.9) * reach * (1 - pull * 0.25)
            let twinkle = 0.4 + 0.6 * abs(sin(t * (0.8 + rnd(i, 22) * 2) + Double(i)))
            let big = rnd(i, 23) > 0.93
            let c = rnd(i, 25)
            puff(g, cos(a) * r, sin(a) * r, big ? 14 : 5 + rnd(i, 24) * 4, c < 0.15 ? .gold : c < 0.3 ? .blue : .white,
                 twinkle * fadeIn * (big ? 0.9 : 0.7))
        }
    }

    /// 은하 소용돌이(별가루 팔 4개)와 가운데 핵
    private func galaxy(_ g: GraphicsContext, _ R: Double, _ s: Double, _ dt: Double) {
        let v = dt < 0 ? clamp((t - 0.8) / (Self.float - 0.8)) * 0.3 + s * 0.7 : max(0, 1 - dt / 0.5)
        let spin = t * 0.5 + s * s * s * 16
        if v > 0 {
            let colors: [P] = [.purple, .blue, .pink]
            for k in 0..<4 {
                for j in 0..<70 {
                    let u = (Double(j) + rnd(j, k + 30)) / 70
                    let r = (0.08 + u) * R * 1.8 * (1 - 0.35 * s)
                    let a = spin + Double(k) * .pi / 2 + u * 4.2 + (rnd(j, k + 40) - 0.5) * 0.5
                    let z = (14 + 46 * (1 - u)) * (0.7 + rnd(j, k + 50) * 0.6)
                    puff(g, cos(a) * r, sin(a) * r * 0.75, z, u < 0.25 ? .gold : colors[(j + k) % 3], v * 0.28 * (1 - u * 0.8))
                }
            }
        }
        // 회오리 동안 커지고, 폭발 직전 한 점으로 오그라든다
        let implode = clamp((t - Self.swirl) / (Self.reveal - Self.swirl))
        let coreR = dt < 0 ? (30 + 90 * s) * (1 - implode * 0.9) : 0
        if coreR > 0 {
            let gold = Self.palette[P.gold.rawValue], purple = Self.palette[P.purple.rawValue]
            let grad = Gradient(stops: [.init(color: .white.opacity(0.4 + 0.6 * s), location: 0),
                                        .init(color: gold.opacity(0.7 * s + 0.1), location: 0.35),
                                        .init(color: purple.opacity(0.5 * s), location: 0.7),
                                        .init(color: .clear, location: 1)])
            g.fill(Path(ellipseIn: CGRect(x: -coreR, y: -coreR, width: coreR * 2, height: coreR * 2)),
                   with: .radialGradient(grad, center: .zero, startRadius: 0, endRadius: coreR))
        }
    }

    /// 별 알갱이: 떠다니다 회오리에서 나선을 그리며 빨려 든다
    private func stream(_ g: GraphicsContext, _ R: Double, _ s: Double) {
        for i in 0..<160 {
            let d = rnd(i, 1) * 0.5
            let le = pow(clamp((s - d) / (1 - d)), 2)
            if le >= 1 { continue }
            let r0 = R * (0.4 + rnd(i, 2) * 1.5)
            let a = rnd(i, 3) * 2 * .pi + t * (0.2 + rnd(i, 4) * 0.4) + le * 9 * .pi
            let r = r0 * (1 - le) + sin(t * 1.5 + Double(i)) * 6
            let alpha = (0.35 + 0.65 * min(s * 2, 1)) * clamp(t / 0.8)
            let c = rnd(i, 5)
            let x = cos(a) * r, y = sin(a) * r * 0.75, z = 8 + rnd(i, 6) * 14 + le * 10
            puff(g, x, y, z * 2.2, c < 0.4 ? .purple : c < 0.7 ? .blue : c < 0.85 ? .pink : .gold, alpha * 0.5)
            puff(g, x, y, z * 0.6, .white, alpha)
        }
    }

    /// 폭발 뒤: 돌아가는 빛살, 테두리 없이 퍼지는 빛 고리 두 겹, 사방으로 튀는 별 파편
    private func burst(_ g: GraphicsContext, _ W: Double, _ H: Double, _ dt: Double) {
        let L = max(W, H)
        let ra = clamp(dt / 0.4) * (0.4 + 0.12 * sin(dt * 3))
        for k in 0..<12 {
            let a = Double(k) / 12 * 2 * .pi + dt * 0.25, wd = 0.12 + 0.08 * rnd(k, 7)
            var wedge = Path()
            wedge.move(to: .zero)
            wedge.addArc(center: .zero, radius: L, startAngle: .radians(a - wd), endAngle: .radians(a + wd), clockwise: false)
            wedge.closeSubpath()
            let c = Self.palette[[P.gold, .purple, .blue][k % 3].rawValue]
            g.fill(wedge, with: .radialGradient(Gradient(colors: [c.opacity(ra * 0.4), .clear]), center: .zero, startRadius: 0, endRadius: L * 0.55))
        }
        for (d, p) in [(0.0, P.gold), (0.15, P.purple)] {
            let q = clamp((dt - d) / 1.0)
            guard q > 0, q < 1 else { continue }
            let r = (1 - pow(1 - q, 3)) * L * 0.7, wdt = 60 + 80 * q
            let c = Self.palette[p.rawValue]
            var e = g
            e.scaleBy(x: 1, y: 0.8)
            let grad = Gradient(stops: [.init(color: c.opacity(0), location: 0), .init(color: c.opacity(0.55 * (1 - q)), location: 0.7),
                                        .init(color: c.opacity(0), location: 1)])
            e.fill(Path(ellipseIn: CGRect(x: -(r + wdt), y: -(r + wdt), width: (r + wdt) * 2, height: (r + wdt) * 2)),
                   with: .radialGradient(grad, center: .zero, startRadius: max(0, r - wdt), endRadius: r + wdt * 0.4))
        }
        let k = exp(-dt * 3)
        for i in 0..<110 {
            let alpha = clamp(1 - dt / (0.8 + rnd(i, 10)))
            if alpha <= 0 { continue }
            let a = rnd(i, 8) * 2 * .pi, d = (250 + rnd(i, 9) * 750) * (1 - k) / 3
            let x = cos(a) * d, y = sin(a) * d * 0.85, z = 6 + rnd(i, 12) * 12
            let c = rnd(i, 11)
            puff(g, x, y, z * 2.5, c < 0.4 ? .gold : c < 0.7 ? .purple : .blue, alpha * 0.6)
            puff(g, x, y, z * 0.6, .white, alpha)
        }
    }

    /// 융합 카드: 솟아오르며 두 바퀴 돌아 앞면으로 멈추고, 광택·홀로그램·반짝임, 아래에 이름
    private func reveal(_ gc: GraphicsContext, _ W: Double, _ H: Double, _ dt: Double) {
        let (c1, c2) = tierColors
        let rw = min(190, (H - 120) * 59 / 86, W * 0.5), rh = rw * 86 / 59
        let turn = 1 - pow(1 - clamp(dt / 1.0), 3)
        let pulse = 0.5 + 0.5 * sin(dt * 3.5)
        let yy = -18 + (dt > 1 ? sin((dt - 1) * 1.6) * 4 : 0)
        let shineT = dt - 0.9
        let state = MatState(x: 0, y: yy, rot: 0, sx: cos((1 - turn) * 4 * .pi), scale: backOut(clamp(dt / 0.6)), whiten: 0, alpha: 1, s: 0)
        card(gc, result, state, w: rw, alpha: 1, whiten: max(0, 1 - dt / 0.35), glow: 30 + 30 * pulse, glowColor: c1, fusion: true) { g, rect in
            guard shineT >= 0 else { return }
            let w = rect.width, h = rect.height
            var g = g
            g.blendMode = .plusLighter
            let dur = tier >= 5 ? 1.6 : 1.4
            for (n, off) in (tier >= 5 ? [0, 0.28] : [0]).enumerated() where shineT >= off {
                let q = tier >= 4 ? ((shineT - off) / dur).truncatingRemainder(dividingBy: 1) : clamp((shineT - off) / 0.9)
                let x0 = -w * 1.2 + q * w * 2.6, bw = w * (n == 0 ? 0.55 : 0.25)
                let edge1 = tier >= 4 ? c1.opacity(0.53) : .white.opacity(0.2), edge2 = tier >= 4 ? c2.opacity(0.53) : .white.opacity(0.2)
                let mid = tier >= 5 ? Color(red: 1, green: 0.94, blue: 0.7).opacity(0.95) : .white.opacity(0.8)
                var sk = g
                sk.concatenate(CGAffineTransform(a: 1, b: 0, c: -0.35, d: 1, tx: 0, ty: 0))
                let grad = Gradient(stops: [.init(color: .clear, location: 0), .init(color: edge1, location: 0.35), .init(color: mid, location: 0.5),
                                            .init(color: edge2, location: 0.65), .init(color: .clear, location: 1)])
                sk.fill(Path(CGRect(x: -w * 2, y: -h, width: w * 4, height: h * 2)),
                        with: .linearGradient(grad, startPoint: CGPoint(x: x0 - bw, y: 0), endPoint: CGPoint(x: x0 + bw, y: 0)))
            }
            if tier >= 4 {  // 홀로그램: 무지개 띠가 천천히 흐른다
                let off = (shineT * 0.4).truncatingRemainder(dividingBy: 1)
                let rainbow: [Color] = [.pink, .yellow, .mint, .cyan, .purple]
                var holo = g
                holo.blendMode = .normal
                holo.opacity = 0.16
                let from = CGPoint(x: rect.minX - off * w, y: rect.minY - off * h)
                holo.fill(Path(rect), with: .linearGradient(Gradient(colors: rainbow + rainbow + [.pink]), startPoint: from,
                                                            endPoint: CGPoint(x: from.x + 2 * w, y: from.y + 2 * h)))
            }
        }
        // 반짝임: 카드 둘레에서 깜빡인다
        var sp = gc
        sp.blendMode = .plusLighter
        let n = tier >= 5 ? 18 : tier >= 4 ? 12 : 7
        for i in 0..<n where dt > 0.6 {
            let tw = max(0, sin((dt - 0.6) * (2 + rnd(i, 13) * 2) + rnd(i, 14) * 6))
            guard tw > 0 else { continue }
            let a = rnd(i, 15) * 2 * .pi, rr = rw * (0.65 + rnd(i, 16) * 0.45)
            let x = cos(a) * rr * 0.9, y = yy + sin(a) * rr * 1.1, z = (4 + rnd(i, 17) * 7) * tw
            var star = Path()
            star.move(to: CGPoint(x: x, y: y - z))
            for (px, py) in [(x + z, y), (x, y + z), (x - z, y), (x, y - z)] {
                star.addQuadCurve(to: CGPoint(x: px, y: py), control: CGPoint(x: x, y: y))
            }
            let c = tier >= 5 && i % 3 != 0 ? Self.palette[P.gold.rawValue] : i % 2 == 1 ? .white : c1
            sp.fill(star, with: .color(c.opacity(tw)))
        }
        // 이름과 안내
        let na = clamp((dt - 0.7) / 0.5)
        var tx = gc
        tx.opacity = na
        tx.addFilter(.shadow(color: c1, radius: 8 * na))
        tx.draw(Text(name).font(.system(size: min(22, W / 18), weight: .semibold)).kerning(1.5).foregroundStyle(.white),
                at: CGPoint(x: 0, y: yy + rh / 2 + 22 + (1 - na) * 8), anchor: .top)
        var hint = gc
        hint.opacity = 0.55 * clamp(dt - 1.6)
        hint.draw(Text("눌러서 닫기").font(.caption).foregroundStyle(.white), at: CGPoint(x: 0, y: yy + rh / 2 + 58), anchor: .top)
    }

    // MARK: 부품

    /// 회오리 진행도 0~1 (떠오름이 끝나는 때부터 회오리 끝까지)
    private func progress(at t: Double) -> Double { clamp((t - Self.float) / (Self.swirl - Self.float)) }

    struct MatState { var x, y, rot, sx, scale, whiten, alpha, s: Double }

    /// 소재 i 의 시각 t 상태 (잔상도 같은 함수로 과거 t 를 그린다). sx 는 Y축 회전의 cos(음수면 뒷면)
    private func mat(_ i: Int, _ t: Double, _ R: Double) -> MatState {
        let n = Double(materials.count), fi = Double(i)
        let s = progress(at: t), e = s * s
        let angle = fi / n * 2 * .pi - .pi / 2 + t * 0.3 + e * 7 * .pi
        let r = R * (1 - e)
        let appear = clamp((t - 0.1 - fi * 0.12) / 0.45)
        let bob = sin(t * 2.2 + fi * 1.3) * 10 * (1 - s) + (1 - backOut(appear)) * 30
        return MatState(x: cos(angle) * r, y: sin(angle) * r * 0.75 + bob,
                        rot: sin(t * 1.6 + fi) * 0.12 * (1 - s) + e * 3 * .pi,
                        sx: cos(sin(t * 1.3 + fi) * 0.45 * (1 - s) + e * 5 * .pi),
                        scale: backOut(appear) * (1 - 0.85 * s),
                        whiten: clamp((s - 0.35) / 0.5),
                        alpha: appear > 0 ? (s < 0.85 ? 1 : 1 - (s - 0.85) / 0.15) : 0,
                        s: s)
    }

    /// 카드 한 장. 뒷면은 CardBack 심볼, 이미지가 아직 없으면 색 판. whiten 은 빛으로 녹아드는 정도.
    private func card(_ gc: GraphicsContext, _ cid: Int?, _ p: MatState, w: Double, alpha: Double, whiten: Double,
                      glow: Double = 0, glowColor: Color = .clear, fusion: Bool = false,
                      after: ((GraphicsContext, CGRect) -> Void)? = nil) {
        guard alpha > 0, p.scale > 0.01 else { return }
        var g = gc
        g.opacity *= alpha
        g.translateBy(x: p.x, y: p.y)
        g.rotate(by: .radians(p.rot))
        g.scaleBy(x: max(abs(p.sx), 0.02) * p.scale, y: p.scale)
        let h = w * 86 / 59
        let rect = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
        let shape = Path(roundedRect: rect, cornerRadius: w * 0.05)
        if glow > 0 {
            var halo = g
            halo.addFilter(.shadow(color: glowColor, radius: glow / 2))
            halo.fill(shape, with: .color(glowColor))
        }
        g.clip(to: shape)
        if p.sx < 0, let back = g.resolveSymbol(id: -1) {
            g.draw(back, in: rect)
        } else if let cid, let image = images[cid] {
            g.draw(g.resolve(Image(nsImage: image)), in: rect)
        } else {
            let colors = fusion ? [Color(red: 0.66, green: 0.47, blue: 0.85), Color(red: 0.29, green: 0.16, blue: 0.43)]
                                : [Color(red: 0.82, green: 0.56, blue: 0.25), Color(red: 0.48, green: 0.29, blue: 0.11)]
            g.fill(shape, with: .linearGradient(Gradient(colors: colors), startPoint: rect.origin, endPoint: CGPoint(x: rect.maxX, y: rect.maxY)))
        }
        after?(g, rect)
        if whiten > 0 { g.fill(shape, with: .color(Color(red: 1, green: 0.97, blue: 0.9).opacity(whiten))) }
    }

    /// 부드러운 빛 점 (선 대신 이걸 겹쳐 성운·별을 그린다)
    private func puff(_ gc: GraphicsContext, _ x: Double, _ y: Double, _ size: Double, _ p: P, _ alpha: Double) {
        guard alpha > 0.003, size > 0.5, let symbol = gc.resolveSymbol(id: p.rawValue) else { return }
        var g = gc
        g.opacity *= min(alpha, 1)
        g.draw(symbol, in: CGRect(x: x - size / 2, y: y - size / 2, width: size, height: size))
    }

    /// 번짐: 많이 흐린 겹 + 조금 흐린 겹 + 선명한 겹을 더한다
    private func bloom(_ gc: GraphicsContext, _ blur: Double, _ content: (GraphicsContext) -> Void) {
        for (radius, opacity) in [(blur, 1.0), (blur * 0.35, 1.0), (0, 0.75)] {
            var g = gc
            g.blendMode = .plusLighter
            g.opacity = opacity
            if radius > 0 { g.addFilter(.blur(radius: radius)) }
            g.drawLayer { layer in
                layer.blendMode = .plusLighter
                content(layer)
            }
        }
    }

    private func clamp(_ x: Double, _ a: Double = 0, _ b: Double = 1) -> Double { min(max(x, a), b) }
    private func backOut(_ p: Double) -> Double { 1 + 2.7 * pow(p - 1, 3) + 1.7 * pow(p - 1, 2) }
    /// 입자마다 고정된 난수 (시간과 무관해서 매 프레임 같은 자리에 그린다)
    private func rnd(_ i: Int, _ k: Int) -> Double {
        let x = sin(Double(i) * 127.1 + Double(k) * 311.7) * 43758.5453
        return x - x.rounded(.down)
    }
}
