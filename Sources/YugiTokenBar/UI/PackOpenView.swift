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
            Button(allFlipped ? "확인" : "모두 뒤집기") {
                if allFlipped {
                    model.showOpening = false
                } else {
                    withAnimation(.easeInOut(duration: 0.4)) { flipped = Set(pulls.indices) }
                }
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .onChange(of: model.openingID) { flipped = [] }
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
                }
                .shadow(color: pull.tier >= 2 ? Rarity.color(tier: pull.tier) : .clear, radius: 10)
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
