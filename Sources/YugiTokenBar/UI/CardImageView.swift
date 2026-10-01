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
                    .grayscale(owned ? 0 : 1)
                    .brightness(owned ? 0 : -0.25)
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

/// 카드 뒷면. YGOPRODeck 뒷면 이미지, 받기 전·실패 시엔 비슷한 갈색 그라데이션.
struct CardBack: View {
    var name = ""
    var glow = false
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
        .shadow(color: glow ? .yellow : .clear, radius: glow ? 10 : 0)
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
