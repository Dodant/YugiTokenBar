import SwiftUI

struct ShopView: View {
    @EnvironmentObject var model: AppModel
    /// 스크롤 위치(위에서부터 pt). 상점을 닫았다 열거나 앱을 다시 켜도 그 자리로.
    @AppStorage("shop.scrollY") private var savedY = 0.0
    @State private var position = ScrollPosition()
    /// 복원 전에 들어오는 0 으로 저장값을 덮지 않게
    @State private var restored = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Button { model.showShop = false } label: {
                    Image(systemName: "chevron.left").font(.body.weight(.semibold)).frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .keyboardShortcut(.cancelAction)
                Text("상점").font(.title3.weight(.semibold))
                Spacer()
                Text(coinText(model.game.state.coins))
                    .font(.callout).monospacedDigit().foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(model.db.eras, id: \.name) { era in
                        EraSection(name: era.name, packs: era.packs)
                    }
                }
            }
            .scrollIndicators(.never)
            .frame(maxHeight: .infinity)
            .scrollPosition($position)
            .onScrollGeometryChange(for: Double.self) { $0.contentOffset.y } action: { _, y in
                if restored { savedY = max(0, y) }
            }
            .task {
                // 첫 레이아웃이 끝난 뒤 옮겨야 적용된다
                await Task.yield()
                position.scrollTo(y: savedY)
                restored = true
            }
        }
    }
}

/// 시대별 접고 펴는 팩 묶음. 접힘 상태는 다음 실행에도 기억한다.
private struct EraSection: View {
    @EnvironmentObject var model: AppModel
    let name: String
    let packs: Range<Int>
    @AppStorage private var expanded: Bool

    init(name: String, packs: Range<Int>) {
        self.name = name
        self.packs = packs
        _expanded = AppStorage(wrappedValue: true, "shop.era.\(name).expanded")
    }

    var body: some View {
        let game = model.game
        let owned = packs.reduce(0) { $0 + game.progress($1).owned }
        let total = packs.reduce(0) { $0 + game.progress($1).total }
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                    Text(name).font(.headline)
                    Text("\(packs.count)팩").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(owned) / \(total)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(packs, id: \.self) { i in
                        PackTile(index: i)
                    }
                }
                .transition(.opacity)
            }
        }
    }
}

/// 상점 그리드 칸: 평소엔 팩 이미지만, 마우스를 올리면 흐려지며 이름·진행도·구매 버튼.
struct PackTile: View {
    @EnvironmentObject var model: AppModel
    let index: Int
    @State private var hover = false

    var body: some View {
        let game = model.game
        let pack = game.db.packs[index]
        let p = game.progress(index)
        let complete = game.isComplete(index)
        PackImageView(pack: pack)
            .blur(radius: hover ? 6 : 0)
            .overlay {
                if hover {
                    VStack(spacing: 6) {
                        Text(pack.name)
                            .font(.callout.weight(.semibold))
                            .multilineTextAlignment(.center)
                        Text("\(pack.date.prefix(4)) · \(p.owned)/\(p.total)")
                            .font(.caption2).monospacedDigit().opacity(0.85)
                        BuyButton(index: index)
                    }
                    .foregroundStyle(.white)
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.black.opacity(0.35))
                    .transition(.opacity)
                }
            }
            .overlay(alignment: .topTrailing) {
                if complete && !hover {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.white, .green).padding(5)
                }
            }
            .clipShape(.rect(cornerRadius: 10))
            .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
            .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
            .help(pack.name)
    }
}

/// 팝오버 바로 구매 줄: 팩 이미지 · 이름 · 진행도 · 구매 버튼.
struct PackRow: View {
    @EnvironmentObject var model: AppModel
    let index: Int

    var body: some View {
        let game = model.game
        let pack = game.db.packs[index]
        let p = game.progress(index)
        HStack(spacing: 12) {
            PackImageView(pack: pack)
                .frame(height: 50)
                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(pack.name).font(.callout.weight(.medium)).lineLimit(1)
                Text(game.isComplete(index) ? "완료 · \(p.owned)/\(p.total)" : "\(pack.date.prefix(4)) · \(p.owned)/\(p.total)")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                ProgressView(value: Double(p.owned), total: Double(p.total)).controlSize(.mini)
                    .tint(game.isComplete(index) ? .green : .accentColor)
            }
            Spacer(minLength: 4)
            BuyButton(index: index)
        }
    }
}

/// 1팩 구매 버튼. 가격(코인)을 그대로 보여준다.
struct BuyButton: View {
    @EnvironmentObject var model: AppModel
    let index: Int

    var body: some View {
        Button(coinText(Balance.packPrice)) {
            model.buy(pack: index)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.capsule)
        .monospacedDigit()
        .disabled(!model.game.canBuy(index))
    }
}
