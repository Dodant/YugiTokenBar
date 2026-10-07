import SwiftUI

/// 카드 이미지. 로딩 중·실패 시 카드 뒷면 + 한국어 이름, owned=false 면 흑백 실루엣.
struct CardImageView: View {
    let db: CardDB
    let cid: Int
    var size: ImageCache.Size = .small
    var owned = true
    @State private var image: NSImage?

    init(db: CardDB, cid: Int, size: ImageCache.Size = .small, owned: Bool = true) {
        self.db = db
        self.cid = cid
        self.size = size
        self.owned = owned
        _image = State(initialValue: db.cards[cid]?.imageId.flatMap { ImageCache.shared.cached($0, size: size) })
    }

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .grayscale(owned ? 0 : 0.8)  // 미보유: 색이 살짝 남는 흑백
                    .brightness(owned ? 0 : -0.20)
            } else {
                CardBack(name: db.cards[cid]?.name ?? "")
            }
        }
        .aspectRatio(59.0 / 86.0, contentMode: .fit)
        .clipShape(.rect(cornerRadius: 7))
        .task(id: cid) {
            guard let imageId = db.cards[cid]?.imageId else { image = nil; return }
            // 캐시에 있으면 뒷면을 거치지 않고 바로 바꾼다
            if let hit = ImageCache.shared.cached(imageId, size: size) { image = hit; return }
            image = nil
            let loaded = await ImageCache.shared.image(imageId, size: size)
            guard !Task.isCancelled else { return }  // cid 가 바뀌어 취소됐으면 새 카드의 이미지를 덮어쓰지 않는다
            image = loaded
        }
    }
}

extension EnvironmentValues {
    /// 설정 [애니메이션 끄기]. 읽을 때는 시스템 동작 줄이기와 합친 `lessMotion`
    @Entry var animationsOff = false
    var lessMotion: Bool { animationsOff || accessibilityReduceMotion }
}

/// 등급 색 (N 회청색 · R 파랑 · SR 금색 · UR 보라 · SE 진분홍).
enum Rarity {
    static let colors: [Color] = [
        Color(red: 0x5C / 255, green: 0x64 / 255, blue: 0x70 / 255),
        Color(red: 0x4A / 255, green: 0x90 / 255, blue: 0xE2 / 255),
        Color(red: 0xF5 / 255, green: 0xC4 / 255, blue: 0x51 / 255),
        Color(red: 0xB0 / 255, green: 0x5C / 255, blue: 0xFF / 255),
        Color(red: 0xFF / 255, green: 0x3D / 255, blue: 0x7F / 255),
    ]

    /// 연출(팩 개봉·융합)용 금빛. SR 등급색과는 다른 값이다.
    static let gold = Color(red: 1, green: 0.8, blue: 0.25)

    /// 아직 획득하지 못한 카드 (밝은 회색, N 회청색과 구분)
    static let locked = Color(red: 0xA0 / 255, green: 0xA0 / 255, blue: 0xA0 / 255)

    static func color(tier: Int) -> Color { colors[min(max(tier, 1), colors.count) - 1] }
    static func color(label: String, owned: Bool = true) -> Color {
        guard owned else { return locked }
        return color(tier: (CardInfo.rarities.firstIndex(of: label) ?? 0) + 1)
    }
}

/// 등급 알약. 등급 색으로 채우고, 미보유면 미획득 색.
struct RarityPill: View {
    let label: String
    var owned = true
    var size: CGFloat = 9

    var body: some View {
        let color = Rarity.color(label: label, owned: owned)
        Text(label)
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(owned && label == "N" ? .white : .black)  // 흰 글자는 어두운 N 바탕에서만 4.5:1 이 넘는다(R·UR·SE 는 3.3~3.6, 검정이면 5.8 이상)
            .padding(.horizontal, size * 0.6)
            .padding(.vertical, size * 0.15)
            .background(color, in: Capsule())
    }
}

/// 카드 뒷면. 번들 이미지, 못 읽으면 비슷한 갈색 그라데이션.
struct CardBack: View {
    var name = ""
    /// 레어 이상이면 등급 색으로 빛난다
    var glow: Color? = nil

    var body: some View {
        ZStack {
            if let image = ImageCache.cardBack {
                Image(nsImage: image).resizable()
            } else {
                RadialGradient(colors: [Color(red: 0.35, green: 0.23, blue: 0.10), Color(red: 0.16, green: 0.09, blue: 0.03)],
                               center: .center, startRadius: 0, endRadius: 90)
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color(red: 0.54, green: 0.35, blue: 0.17), lineWidth: 2))
            }
            if !name.isEmpty {
                Text(name)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 3)
                    .frame(maxWidth: .infinity)
                    .background(.black.opacity(0.55))
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .aspectRatio(59.0 / 86.0, contentMode: .fit)
        .clipShape(.rect(cornerRadius: 7))
        .shadow(color: glow ?? .clear, radius: glow == nil ? 0 : 10)
    }
}

/// 팩 봉투 이미지. 없거나 로딩 중이면 그라데이션.
struct PackImageView: View {
    let pack: Pack
    @State private var image: NSImage?

    init(pack: Pack) {
        self.pack = pack
        _image = State(initialValue: ImageCache.shared.cachedPack(pack))
    }

    var body: some View {
        // 봉투 비율이 원본마다 0.52~0.56 이라 0.53 칸에 채우고 넘치는 가장자리만 자른다
        Color.clear
            .aspectRatio(0.53, contentMode: .fit)
            .overlay {
                if let image {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
            .clipShape(.rect(cornerRadius: 6))
        .task(id: pack.pid) {
            // 캐시에 있으면 그라데이션을 거치지 않고 바로 바꾼다
            if let hit = ImageCache.shared.cachedPack(pack) { image = hit; return }
            image = nil
            let loaded = await ImageCache.shared.packImage(pack)
            guard !Task.isCancelled else { return }
            image = loaded
        }
    }
}

/// 마우스를 올리고 움직이면 실물 카드를 빛에 비춰 보듯 커서 쪽으로 기울고(스프링이라 살짝 출렁임), 빛 반사가 커서를 따라간다.
/// N·R 흰 반사, SR 더 밝게, UR·SE 무지개 홀로그램을 덧입힌다. 동작 줄이기·애니메이션 끄기면 기울기 없이 반사만 약하게.
private struct CardTilt: ViewModifier {
    let tier: Int
    let angleScale: Double
    let enabled: Bool
    @Environment(\.lessMotion) private var reduceMotion
    /// 카드 안 커서 위치 (-1…1), 밖이면 nil
    @State private var point: CGPoint?
    @State private var size: CGSize = .zero

    private static let maxAngle = 8.0
    private static let hoverScale = 1.03
    private static let spring = Animation.interpolatingSpring(stiffness: 180, damping: 16)
    private static let glare = (normal: 0.14, bright: 0.22, holo: 0.18)
    private static let holoOpacity = 0.14
    private static let shadowShift = 4.0

    func body(content: Content) -> some View {
        let on = enabled && point != nil
        let p = enabled ? point ?? .zero : .zero
        let angle = reduceMotion ? 0 : Self.maxAngle * angleScale
        let lift = on && !reduceMotion
        content
            .overlay { if enabled { reflection(p).opacity(on ? (reduceMotion ? 0.5 : 1) : 0).allowsHitTesting(false) } }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            .onContinuousHover { phase in
                guard case .active(let loc) = phase, size.width > 0, size.height > 0 else { point = nil; return }
                point = CGPoint(x: min(max(loc.x / size.width * 2 - 1, -1), 1), y: min(max(loc.y / size.height * 2 - 1, -1), 1))
            }
            // 커서 쪽 가장자리가 안으로 눌린다
            .rotation3DEffect(.degrees(-p.y * angle), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
            .rotation3DEffect(.degrees(p.x * angle), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .scaleEffect(lift ? Self.hoverScale : 1)
            .shadow(color: .black.opacity(lift ? 0.25 : 0), radius: 8,
                    x: -p.x * Self.shadowShift * angleScale, y: -p.y * Self.shadowShift * angleScale + 2)
            .animation(reduceMotion ? .easeOut(duration: 0.15) : Self.spring, value: point)
    }

    private func reflection(_ p: CGPoint) -> some View {
        let center = UnitPoint(x: (p.x + 1) / 2, y: (p.y + 1) / 2)
        let holo = tier >= 4  // RareEffect 의 UR 판정과 같다
        let glare = holo ? Self.glare.holo : tier >= 3 ? Self.glare.bright : Self.glare.normal
        return ZStack {
            if holo {
                AngularGradient(colors: [.red, .orange, .yellow, .green, .cyan, .blue, .purple, Rarity.color(tier: tier), .red],
                                center: center, angle: .degrees(p.x * 60 + p.y * 30))
                    .opacity(Self.holoOpacity)
            }
            GeometryReader { g in
                RadialGradient(colors: [.white.opacity(glare), .clear], center: center,
                               startRadius: 0, endRadius: max(g.size.width, g.size.height) * 0.7)
            }
        }
        .blendMode(.plusLighter)
        .clipShape(.rect(cornerRadius: 7))
    }
}

extension View {
    /// 카드 호버 기울기·반사. angleScale 은 작은 썸네일에서 각도를 줄일 때, enabled 는 앞면이 보일 때만 켤 때
    func cardTilt(tier: Int, angleScale: Double = 1, enabled: Bool = true) -> some View {
        modifier(CardTilt(tier: tier, angleScale: angleScale, enabled: enabled))
    }
}
