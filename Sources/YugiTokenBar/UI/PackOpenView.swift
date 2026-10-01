import SwiftUI

struct PackOpenView: View {
    @EnvironmentObject var model: AppModel
    @State private var flipped: Set<Int> = []

    var body: some View {
        let pulls = model.opening
        VStack(spacing: 14) {
            if !pulls.isEmpty {
                HStack(spacing: 10) {
                    ForEach(Array(pulls.enumerated()), id: \.offset) { i, pull in
                        FlipCard(pull: pull, db: model.db, flipped: flipped.contains(i))
                            .frame(width: 140)
                            .onTapGesture { withAnimation(.easeInOut(duration: 0.4)) { _ = flipped.insert(i) } }
                    }
                }
                Button("모두 뒤집기") {
                    withAnimation(.easeInOut(duration: 0.4)) { flipped = Set(pulls.indices) }
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(flipped.count == pulls.count)
            } else {
                ContentUnavailableView("열 팩이 없어요", systemImage: "shippingbox",
                                       description: Text("상점에서 팩을 사면 여기서 열려요"))
            }
        }
        .padding(24)
        .background(.background)
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
                .overlay(alignment: .bottomLeading) { tag(pull.label, .black.opacity(0.7)) }
                .overlay(alignment: .topTrailing) {
                    if pull.isNew { tag("NEW", .pink) }
                }
                .shadow(color: pull.tier >= 2 ? .yellow : .clear, radius: 10)
                .rotation3DEffect(.degrees(flipped ? 0 : -180), axis: (x: 0, y: 1, z: 0))
                .opacity(flipped ? 1 : 0)
            CardBack(glow: pull.tier >= 2)
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
