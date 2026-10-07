import SwiftUI

/// "융합 가능" 목록. inspector 클로저는 부모가 다시 그려져도 갱신되지 않을 때가 있어 모델을 직접 구독하는 뷰로 뺐다.
/// 누르면 그 카드로 이동해 상세(융합 버튼)를 연다
struct FusableSection: View {
    @Environment(AppModel.self) private var model
    let selected: Set<Int>
    let cache: FusableCache
    let jump: (Int) -> Void

    var body: some View {
        let cids = cache.list(model.game)
        if !cids.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label("융합 가능 · \(cids.count)", systemImage: "arrow.triangle.merge")
                    .font(.headline)
                    .foregroundStyle(Palette.fusion)
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(cids, id: \.self) { cid in
                            Button { jump(cid) } label: {
                                HStack(spacing: 8) {
                                    CardImageView(db: model.db, cid: cid, owned: false).frame(width: 22)
                                    Text(model.db.cards[cid]?.name ?? "").lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .contentShape(.rect)
                                .background(selected == [cid] ? Color.accentColor.opacity(0.18) : .clear, in: .rect(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: min(CGFloat(cids.count) * 38, 190))
            }
            .padding(12)
            Divider()
        }
    }
}

/// 마지막 융합 가능 목록. 카드를 클릭해 선택만 바뀌면 8천 장을 다시 훑지 않는다 (보유·설정·시대가 같으면 결과도 같다)
@MainActor final class FusableCache {
    private var key: (owned: [Int: Int], on: Bool, era: String)?
    private var cids: [Int] = []

    func list(_ game: Game) -> [Int] {
        let s = game.state
        if let key, key.owned == s.owned, key.on == s.fusionOnly, key.era == s.eraLimit { return cids }
        cids = game.fusable
        key = (s.owned, s.fusionOnly, s.eraLimit)
        return cids
    }
}
