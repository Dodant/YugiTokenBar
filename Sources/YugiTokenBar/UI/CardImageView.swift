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
                    .brightness(owned ? 0 : -0.45)
            } else {
                CardBack(name: db.cards[cid]?.name ?? "")
            }
        }
        .aspectRatio(59.0 / 86.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .task(id: cid) {
            image = nil
            if let imageId = db.cards[cid]?.imageId {
                image = await ImageCache.shared.image(imageId, size: size)
            }
        }
    }
}

struct CardBack: View {
    var name = ""
    var glow = false

    var body: some View {
        ZStack {
            RadialGradient(colors: [Color(red: 0.35, green: 0.23, blue: 0.10), Color(red: 0.16, green: 0.09, blue: 0.03)],
                           center: .center, startRadius: 0, endRadius: 90)
            Text("遊")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Color(red: 0.85, green: 0.64, blue: 0.29))
            if !name.isEmpty {
                Text(name)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(4)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .aspectRatio(59.0 / 86.0, contentMode: .fit)
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color(red: 0.54, green: 0.35, blue: 0.17), lineWidth: 2))
        .shadow(color: glow ? .yellow : .clear, radius: glow ? 10 : 0)
    }
}

/// 팩 봉투 이미지. 없거나 로딩 중이면 그라데이션.
struct PackImageView: View {
    let pack: Pack
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable()
            } else {
                LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .aspectRatio(301.0 / 534.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .task(id: pack.pid) {
            image = nil
            if let code = pack.setCode { image = await ImageCache.shared.packImage(code) }
        }
    }
}
