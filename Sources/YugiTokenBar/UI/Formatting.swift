import SwiftUI

/// 마우스를 올리면 말풍선으로 설명을 띄운다.
// ponytail: 메뉴바 패널(.window)에서는 .help 툴팁이 뜨지 않아 hover + popover 로 대신한다. 일반 창(컬렉션)은 .help 그대로.
private struct HoverHint: ViewModifier {
    let text: Text
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .onHover { shown = $0 }
            .popover(isPresented: $shown, arrowEdge: .top) {
                text.font(.callout).padding(10).fixedSize()
                    .presentationBackground(.thickMaterial)  // 기본 유리보다 덜 비치게
            }
    }
}

extension View {
    func hoverHint(_ text: LocalizedStringKey) -> some View { modifier(HoverHint(text: Text(text))) }
    /// 카드 이름처럼 이미 그 언어인 데이터 문자열 (키로 찾지 않는다)
    func hoverHint(verbatim text: String) -> some View { modifier(HoverHint(text: Text(verbatim: text))) }

    /// 패널 안 스크롤의 아래 끝. 살짝 흐려지며(재질 띠) 투명해져서 글자가 반 토막으로 잘려 보이지 않는다.
    /// 끝까지 내리면 마지막 줄이 띠 위에 오도록 내용 아래에 띠 높이만큼 여백을 둔다.
    func panelScrollBottom(_ height: CGFloat = 16) -> some View {
        let fade = LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
        return contentMargins(.bottom, height, for: .scrollContent)
            .overlay(alignment: .bottom) {
                Rectangle().fill(.ultraThinMaterial)
                    .mask(LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom))
                    .frame(height: height)
                    .allowsHitTesting(false)
            }
            .mask { VStack(spacing: 0) { Color.black; fade.frame(height: height) } }
    }
}

/// 색을 넣는 진행 막대. ProgressView 는 .tint 가 외관(라이트·다크)을 바꾸면 풀려 기본 강조색이 되어서 직접 그린다.
struct TintBar: View {
    let value: Double
    let tint: Color
    var height: CGFloat = 4

    var body: some View {
        Capsule().fill(.quaternary)
            .overlay(alignment: .leading) {
                GeometryReader { g in Capsule().fill(tint).frame(width: g.size.width * min(max(value, 0), 1)) }
            }
            .frame(height: height)
    }
}

/// 코인 표기: ⓒ 1,000
/// 만 단위부터 K·M (12,345 → 12.3K, 1,000,000 → 1M). 메뉴바와 `coinText`가 같이 쓴다
func shortCoins(_ n: Int) -> String {
    guard abs(n) >= 10_000 else { return n.formatted() }
    return n.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)).locale(Locale(identifier: "en_US")))
}

func coinText(_ n: Int) -> String { "ⓒ \(shortCoins(n))" }

/// 1,000 미만은 그대로 (0.5K 를 "0K" 로 보이지 않게)
func shortTokens(_ n: Int) -> String {
    n < 1_000 ? "\(n)" : n >= 1_000_000 ? String(format: "%.1fM", Double(n) / 1e6) : String(format: "%.0fK", Double(n) / 1e3)
}
