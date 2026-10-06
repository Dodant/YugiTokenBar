import SwiftUI

/// 카드 이미지. 로딩 중·실패 시 카드 뒷면 + 한국어 이름, owned=false 면 흑백 실루엣.
struct CardImageView: View {
    let db: CardDB
    let cid: Int
    var size: ImageCache.Size = .small
    var owned = true
    @State private var image: NSImage?

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
            image = nil
            if let imageId = db.cards[cid]?.imageId {
                image = await ImageCache.shared.image(imageId, size: size)
            }
        }
    }
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
            .foregroundStyle(!owned || label == "SR" ? .black : .white)  // 밝은 배경(SR 금색·미획득 회색)엔 흰 글자가 안 읽힌다
            .padding(.horizontal, size * 0.6)
            .padding(.vertical, size * 0.15)
            .background(color, in: Capsule())
    }
}

/// 카드 뒷면. YGOPRODeck 뒷면 이미지, 받기 전·실패 시엔 비슷한 갈색 그라데이션.
struct CardBack: View {
    var name = ""
    /// 레어 이상이면 등급 색으로 빛난다
    var glow: Color? = nil
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
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
        .task { image = await ImageCache.shared.cardBack() }
    }
}

/// 팩 봉투 이미지. 없거나 로딩 중이면 그라데이션.
struct PackImageView: View {
    let pack: Pack
    @State private var image: NSImage?

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
            image = nil
            image = await ImageCache.shared.packImage(pack)
        }
    }
}
