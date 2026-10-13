import SwiftUI

/// "융합 가능" 목록. inspector 클로저는 부모가 다시 그려져도 갱신되지 않을 때가 있어 모델을 직접 구독하는 뷰로 뺐다.
/// 누르면 그 카드로 이동해 상세(융합 버튼)를 연다. 아래 [모두 융합]은 확인 뒤 목록을 다 만든다
struct FusableSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.workMode) private var workMode
    let selected: Set<Int>
    /// 마지막 융합 가능 목록. 카드를 클릭해 선택만 바뀌면 8천 장을 다시 훑지 않는다
    let cache: GameMemo<[Int]>
    let jump: (Int) -> Void
    @AppStorage("dex.fusableExpanded") private var expanded = true
    @State private var confirmAll = false
    /// [모두 융합]으로 만든 장 수 (결과 알림)
    @State private var made = 0

    var body: some View {
        let cids = cache(model.game)
        // 다 만들면 목록이 사라지므로 결과 알림은 그 바깥에 단다
        VStack(spacing: 0) { if !cids.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Label("융합 가능 · \(cids.count)", systemImage: "arrow.triangle.merge")
                        Spacer()
                        DisclosureChevron(expanded: expanded)
                    }
                    .font(.headline)
                    .foregroundStyle(Palette.fusion)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                if expanded { ScrollView {
                    VStack(spacing: 2) {
                        ForEach(cids, id: \.self) { cid in
                            Button { jump(cid) } label: {
                                HStack(spacing: 8) {
                                    if !workMode {  // 업무 모드면 그림 자리 없이 이름만
                                        CardImageView(db: model.db, cid: cid, owned: false).frame(width: 22)
                                    }
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
                .frame(maxHeight: min(CGFloat(cids.count) * 38, 190)) }
                // 일괄 융합: 확인 뒤 목록을 다 만든다 (연출 없이, 만든 융합이 소재인 것도 이어서)
                HStack {
                    Spacer()
                    Button { confirmAll = true } label: { Label("모두 융합", systemImage: "arrow.triangle.merge") }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                        .controlSize(.small)
                        .help("융합 가능한 카드를 한 번에 만들어요")
                        .confirmationDialog("\(cids.count)장을 모두 융합할까요?", isPresented: $confirmAll) {
                            Button("모두 융합") { made = model.fuseAll() }
                        } message: {
                            Text("소재 카드는 1장씩 남아요. 소재가 겹쳐 모자라면 목록 앞 카드부터 만들어요.")
                        }
                }
            }
            .padding(12)
            Divider()
        } }
        .alert("\(made)장을 융합했어요", isPresented: Binding(get: { made > 0 }, set: { if !$0 { made = 0 } })) {
            Button("확인") {}
        } message: {
            Text("최근 획득에서 만든 카드를 볼 수 있어요")
        }
    }
}
