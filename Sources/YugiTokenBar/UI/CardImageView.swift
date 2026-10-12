import SwiftUI

/// 카드 이미지. 로딩 중·실패 시 카드 뒷면 + 고른 언어의 카드 이름, owned=false 면 흑백 실루엣.
struct CardImageView: View {
    let db: CardDB
    let cid: Int
    var size: ImageCache.Size = .small
    var owned = true
    /// 업무 모드여도 실제 그림 (컬렉션 정보 패널)
    var showInWorkMode = false
    @Environment(\.workMode) private var workMode
    @State private var image: NSImage?

    init(db: CardDB, cid: Int, size: ImageCache.Size = .small, owned: Bool = true, showInWorkMode: Bool = false) {
        self.db = db
        self.cid = cid
        self.size = size
        self.owned = owned
        self.showInWorkMode = showInWorkMode
        _image = State(initialValue: db.cards[cid]?.imageId.flatMap { ImageCache.shared.cached($0, size: size, force: showInWorkMode) })
    }

    private var hidden: Bool { workMode && !showInWorkMode }

    var body: some View {
        ZStack {
            if hidden {
                CardPlaceholder(name: db.cards[cid]?.name ?? "", owned: owned)
            } else if let image {
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
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Palette.cardRim, lineWidth: 1))
        .task(id: hidden ? nil : cid) {  // 숨길 때는 nil 이라 로딩하지 않는다
            guard !hidden else { image = nil; return }
            guard let imageId = db.cards[cid]?.imageId else { image = nil; return }
            // 캐시에 있으면 뒷면을 거치지 않고 바로 바꾼다
            if let hit = ImageCache.shared.cached(imageId, size: size, force: showInWorkMode) { image = hit; return }
            image = nil
            let loaded = await ImageCache.shared.image(imageId, size: size, force: showInWorkMode)
            guard !Task.isCancelled else { return }  // cid 가 바뀌어 취소됐으면 새 카드의 이미지를 덮어쓰지 않는다
            image = loaded
        }
    }
}

extension EnvironmentValues {
    /// 설정 [애니메이션 끄기]. 읽을 때는 시스템 동작 줄이기와 합친 `lessMotion`
    @Entry var animationsOff = false
    /// 업무 모드 (카드·팩 이미지를 그리지 않는다)
    @Entry var workMode = false
    var lessMotion: Bool { animationsOff || accessibilityReduceMotion }
}

/// 등급 색 (N 회청색 · R 파랑 · SR 금색 · UR 보라 · SE 진분홍).
enum Rarity {
    static let colors: [Color] = [
        // N 은 다크 배경에서 묻히지 않게 밝힌다 (#2A2A2C 위 4.8:1)
        Color(light: Color(red: 0x5C / 255, green: 0x64 / 255, blue: 0x70 / 255), dark: Color(red: 0x8E / 255, green: 0x96 / 255, blue: 0xA3 / 255)),
        Color(red: 0x4A / 255, green: 0x90 / 255, blue: 0xE2 / 255),
        Color(red: 0xF5 / 255, green: 0xC4 / 255, blue: 0x51 / 255),
        Color(red: 0xB0 / 255, green: 0x5C / 255, blue: 0xFF / 255),
        Color(red: 0xFF / 255, green: 0x3D / 255, blue: 0x7F / 255),
    ]

    /// 연출(팩 개봉·융합)용 금빛. SR 등급색과는 다른 값이다.
    static let gold = Color(red: 1, green: 0.8, blue: 0.25)

    /// 아직 획득하지 못한 카드 (밝은 회색, N 회청색과 구분)
    static let locked = Color(red: 0xA0 / 255, green: 0xA0 / 255, blue: 0xA0 / 255)

    /// 알약 바탕. 밝은 등급 색 위 검정 글자는 탁해 보여서, SR 말고는 한 단계 진하게 하고 흰 글자(5.1:1 이상)
    static let pillColors: [Color] = [
        Color(red: 0x5C / 255, green: 0x64 / 255, blue: 0x70 / 255),
        Color(red: 0x2F / 255, green: 0x6D / 255, blue: 0xB5 / 255),
        Color(red: 0xF5 / 255, green: 0xC4 / 255, blue: 0x51 / 255),
        Color(red: 0x8A / 255, green: 0x3F / 255, blue: 0xD6 / 255),
        Color(red: 0xD2 / 255, green: 0x1E / 255, blue: 0x5F / 255),
    ]

    static func color(tier: Int) -> Color { colors[min(max(tier, 1), colors.count) - 1] }
    static func color(label: String, owned: Bool = true) -> Color {
        guard owned else { return locked }
        return color(tier: (CardInfo.rarities.firstIndex(of: label) ?? 0) + 1)
    }
}

/// 등급 외에 라이트·다크 값을 같이 두는 색. 화면에서 colorScheme 으로 나누지 않고 여기서 고른다.
/// 글자색은 라이트는 흰 바탕, 다크는 #2A2A2C 바탕에서 4.5:1 이상.
enum Palette {
    /// 다크에서는 그림자가 안 보여서 카드 가장자리에 얇은 밝은 테두리
    static let cardRim = Color(light: .clear, dark: .white.opacity(0.2))
    /// 주의 글자 (새 버전, 한도 60% 이상). 시스템 주황은 흰 바탕에서 2.2:1
    static let warning = Color(light: Color(red: 0xB2 / 255, green: 0x50 / 255, blue: 0), dark: .orange)
    /// 위험 글자 (한도 85% 이상)
    static let danger = Color(light: Color(red: 0xC4 / 255, green: 0x28 / 255, blue: 0x1C / 255), dark: Color(red: 1, green: 0x7B / 255, blue: 0x72 / 255))
    /// 융합 강조 글자
    static let fusion = Color(light: Color(red: 0x96 / 255, green: 0x36 / 255, blue: 0xC9 / 255), dark: Color(red: 0xD8 / 255, green: 0x8C / 255, blue: 1))
    /// 카드 위 흰 글자 배지 바탕. 카드 이미지 위라 외관과 상관없이 고정, 흰 글자 5:1 이상
    static let badgeNew = Color(red: 0xC2 / 255, green: 0x18 / 255, blue: 0x5B / 255)
    static let badgeGain = Color(red: 0x1B / 255, green: 0x7F / 255, blue: 0x3B / 255)
    static let badgeLoss = Color(red: 0xC6 / 255, green: 0x28 / 255, blue: 0x28 / 255)
    /// 상점 팩 도장(COMPLETE·FUSION ONLY). 팩 이미지 위 흰 바탕이라 외관과 상관없이 고정
    static let stampComplete = Color(red: 0x1B / 255, green: 0x7F / 255, blue: 0x3B / 255)
    static let stampFusion = Color(red: 0x96 / 255, green: 0x36 / 255, blue: 0xC9 / 255)
    /// 카드 틀 색 (업무 모드 줄의 세로 막대). 라이트는 흰 바탕에서 보이게 진하게, 다크는 밝게
    static let frameNormal = Color(light: hex(0xC9A13A), dark: hex(0xFDE68A))
    static let frameEffect = Color(light: hex(0xE0712F), dark: hex(0xFF8B53))
    static let frameRitual = Color(light: hex(0x5F86B3), dark: hex(0x9DB5CC))
    static let frameFusion = Color(light: hex(0x8A5CB5), dark: hex(0xB89BD6))
    static let frameSynchro = Color(light: hex(0xA6A6A6), dark: hex(0xE6E6E6))
    static let frameXyz = Color(light: hex(0x1C1C1C), dark: hex(0x8C8C8C))
    static let frameLink = Color(light: hex(0x1F3FA8), dark: hex(0x6B86FF))
    static let frameSpell = Color(light: hex(0x1D9E74), dark: hex(0x3FC79A))
    static let frameTrap = Color(light: hex(0xBC5A84), dark: hex(0xE07BA8))

    private static func hex(_ v: Int) -> Color {
        Color(red: Double(v >> 16 & 0xFF) / 255, green: Double(v >> 8 & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    /// 카드 종류의 틀 색. 펜듈럼은 위 틀 색 → 아래 마법 초록
    static func frame(_ card: CardInfo) -> AnyShapeStyle {
        if card.kindCode == "spell" { return AnyShapeStyle(frameSpell) }
        if card.kindCode == "trap" { return AnyShapeStyle(frameTrap) }
        let summons = card.summons ?? []
        // ponytail: 일반/효과는 언어 공용 코드가 없어 type 칸의 세 언어 낱말로 가른다. 코드가 생기면 그걸로
        let normal = card.type?.split(separator: "/").contains { ["일반", "Normal", "通常"].contains($0) } ?? false
        let base = summons.contains("link") ? frameLink : summons.contains("xyz") ? frameXyz
            : summons.contains("synchro") ? frameSynchro : summons.contains("fusion") ? frameFusion
            : summons.contains("ritual") ? frameRitual : normal ? frameNormal : frameEffect
        return summons.contains("pendulum")
            ? AnyShapeStyle(LinearGradient(colors: [base, frameSpell], startPoint: .top, endPoint: .bottom))
            : AnyShapeStyle(base)
    }
}

extension Color {
    /// 라이트·다크 값을 같이 갖는 색. 외관이 바뀌면 다시 그릴 때 알아서 바뀐다
    init(light: Color, dark: Color) {
        self.init(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(dark) : NSColor(light) })
    }
}

/// 등급 알약. 등급 색으로 채우고, 미보유면 미획득 색.
struct RarityPill: View {
    let label: String
    var owned = true
    var size: CGFloat = 9
    /// 줄 목록용: 가장 넓은 등급 알약만큼 자리를 잡아(왼쪽 정렬) 뒤 글자의 시작을 맞춘다
    var aligned = false

    var body: some View {
        if aligned {
            ZStack(alignment: .leading) {
                ForEach(CardInfo.rarities, id: \.self) { pill($0).hidden() }
                pill(label)
            }
        } else {
            pill(label)
        }
    }

    private func pill(_ label: String) -> some View {
        let tier = (CardInfo.rarities.firstIndex(of: label) ?? 0) + 1
        let color = owned ? Rarity.pillColors[min(max(tier, 1), Rarity.pillColors.count) - 1] : Rarity.locked
        return Text(label)
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(owned && tier != 3 ? .white : .black)  // 금색 SR·미획득 회색만 검정 글자
            .padding(.horizontal, size * 0.6)
            .padding(.vertical, size * 0.15)
            .background(color, in: Capsule())
    }
}

/// 업무 모드 줄의 카드 종류 표시 (등급 알약 앞). 미보유면 흐리게.
/// 기본은 세로 막대, shapes 면 몬스터는 동그라미·마법·함정은 네모 (폭이 같다)
struct FrameBar: View {
    let card: CardInfo?
    var owned = true
    var shapes = false

    var body: some View {
        let style = card.map(Palette.frame) ?? AnyShapeStyle(.clear)
        Group {
            if !shapes {
                RoundedRectangle(cornerRadius: 1.5).fill(style).frame(width: 3, height: 16)
            } else if card?.kindCode == nil {
                Circle().fill(style).frame(width: 10, height: 10)
            } else {
                RoundedRectangle(cornerRadius: 2).fill(style).frame(width: 10, height: 10)
            }
        }
        .opacity(owned ? 1 : 0.4)
    }
}

/// 업무 모드에서 이미지 대신 그리는 밋밋한 상자. 시스템 색만 쓴다.
private struct CardPlaceholder: View {
    var name = ""
    var owned = true

    var body: some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(.fill.tertiary)
            .overlay {
                if !name.isEmpty {
                    Text(name)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(owned ? .secondary : .tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 3)
                }
            }
    }
}

/// 카드 뒷면. 번들 이미지, 못 읽으면 비슷한 갈색 그라데이션.
struct CardBack: View {
    var name = ""
    /// 레어 이상이면 등급 색으로 빛난다
    var glow: Color? = nil
    @Environment(\.workMode) private var workMode

    var body: some View {
        if workMode {
            CardPlaceholder(name: name)
                .aspectRatio(59.0 / 86.0, contentMode: .fit)
        } else {
            back
        }
    }

    private var back: some View {
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
    @Environment(\.workMode) private var workMode
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
                if workMode {
                    Rectangle().fill(.fill.tertiary)
                } else if let image {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
            .clipShape(.rect(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.cardRim, lineWidth: 1))
        .task(id: workMode ? nil : pack.pid) {
            guard !workMode else { image = nil; return }
            // 캐시에 있으면 그라데이션을 거치지 않고 바로 바꾼다
            if let hit = ImageCache.shared.cachedPack(pack) { image = hit; return }
            image = nil
            let loaded = await ImageCache.shared.packImage(pack)
            guard !Task.isCancelled else { return }
            image = loaded
        }
    }
}

/// 마우스를 올리고 움직이면 실물 카드를 빛에 비춰 보듯 커서 쪽으로 기울고, 빛 반사가 커서를 따라간다. 진입·이탈만 스프링으로 움직인다.
/// N·R 흰 반사, SR 더 밝게, UR·SE 무지개 홀로그램을 덧입힌다. 동작 줄이기·애니메이션 끄기면 기울기 없이 반사만 약하게.
private struct CardTilt: ViewModifier {
    let tier: Int
    let angleScale: Double
    let enabled: Bool
    @Environment(\.lessMotion) private var reduceMotion
    @Environment(\.workMode) private var workMode
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
        let enabled = enabled && !workMode  // 업무 모드면 기울기·반사·홀로그램 없음
        let on = enabled && point != nil
        let p = enabled ? point ?? .zero : .zero
        let angle = reduceMotion ? 0 : Self.maxAngle * angleScale
        let lift = on && !reduceMotion
        content
            .overlay { if enabled { reflection(p).opacity(on ? (reduceMotion ? 0.5 : 1) : 0).allowsHitTesting(false) } }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            .onContinuousHover { phase in
                guard enabled, case .active(let loc) = phase, size.width > 0, size.height > 0 else {
                    if point != nil { point = nil }
                    return
                }
                let next = CGPoint(x: min(max(loc.x / size.width * 2 - 1, -1), 1), y: min(max(loc.y / size.height * 2 - 1, -1), 1))
                // 1pt 미만의 이동은 무시해 작은 썸네일의 과도한 갱신을 줄인다.
                if let point, abs(next.x - point.x) * size.width < 2,
                   abs(next.y - point.y) * size.height < 2 { return }
                point = next
            }
            // 커서 쪽 가장자리가 안으로 눌린다
            .rotation3DEffect(.degrees(-p.y * angle), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
            .rotation3DEffect(.degrees(p.x * angle), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .scaleEffect(lift ? Self.hoverScale : 1)
            .shadow(color: .black.opacity(lift ? 0.25 : 0), radius: 8,
                    x: -p.x * Self.shadowShift * angleScale, y: -p.y * Self.shadowShift * angleScale + 2)
            .animation(reduceMotion ? .easeOut(duration: 0.15) : Self.spring, value: on)
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
            RadialGradient(colors: [.white.opacity(glare), .clear], center: center,
                           startRadius: 0, endRadius: max(size.width, size.height) * 0.7)
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
