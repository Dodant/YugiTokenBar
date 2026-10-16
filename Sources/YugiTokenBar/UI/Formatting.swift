#if os(macOS)
import SwiftUI

/// 마우스를 올리면 말풍선으로 설명을 띄운다.
// ponytail: 메뉴바 패널(.window)에서는 .help 툴팁이 뜨지 않아 hover + popover 로 대신한다. 일반 창(컬렉션)은 .help 그대로.
private struct HoverHint: ViewModifier {
    let text: Text
    /// 기울기가 있는 카드 썸네일만: 기울기 진입과 재질 팝오버 생성을 같은 순간에 시작하지 않는다
    var delayed = false
    @State private var hovered = false
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .onHover {
                hovered = $0
                if !$0 { shown = false }
            }
            .task(id: hovered) {
                guard hovered else { return }
                if delayed { do { try await Task.sleep(for: .milliseconds(350)) } catch { return } }
                shown = true
            }
            .popover(isPresented: $shown, arrowEdge: .top) {
                text.font(.callout).padding(10).fixedSize()
                    .presentationBackground(.thickMaterial)  // 기본 유리보다 덜 비치게
            }
    }
}

extension View {
    func hoverHint(_ text: LocalizedStringKey) -> some View { modifier(HoverHint(text: Text(text))) }
    /// 카드 이름처럼 이미 그 언어인 데이터 문자열 (키로 찾지 않는다). 카드 썸네일에 쓰여 0.35초 늦게 뜬다
    func hoverHint(verbatim text: String) -> some View { modifier(HoverHint(text: Text(verbatim: text), delayed: true)) }

    /// 패널 안 스크롤의 아래 끝. 시스템 스크롤 가장자리 효과로 흐려지며 사라져 글자가 반 토막으로 잘려 보이지 않는다.
    /// 효과는 안전 영역 인셋 아래에만 그려지므로 빈 인셋을 두고, 끝까지 내리면 마지막 줄이 그 위에 온다.
    func panelScrollBottom() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 16).allowsHitTesting(false) }
            .scrollEdgeEffectStyle(.soft, for: .bottom)
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

/// 팩·덱 진행 막대. 다 모으면 초록
struct ProgressBar: View {
    let owned: Int
    let total: Int

    var body: some View {
        TintBar(value: Double(owned) / Double(max(total, 1)), tint: total > 0 && owned == total ? Palette.complete : .accentColor)
    }
}

/// 보유/전체 숫자. 다 모으면 보유와 초록 체크 ("136 ✓")
struct ProgressCount: View {
    let owned: Int
    let total: Int

    var body: some View {
        HStack(spacing: 3) {
            if total > 0 && owned == total {
                Text(verbatim: "\(owned)")
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.complete)
            } else {
                Text("\(owned)/\(total)")
            }
        }
    }
}

/// 접고 펴는 묶음 헤더의 꺾쇠. 펴면 아래를 향한다
struct DisclosureChevron: View {
    let expanded: Bool

    var body: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.bold))
            .rotationEffect(.degrees(expanded ? 90 : 0))
    }
}

#endif
