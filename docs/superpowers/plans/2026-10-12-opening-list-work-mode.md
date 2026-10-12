# 업무 모드 개봉 화면 줄 목록 (2026-10-12)

기준: 스펙 6절 외관의 업무 모드 문장("팩·무료 카드 개봉 화면도 …"). 브랜치 `feat/work-mode` 위에 이어서. 규칙은 `CLAUDE.md`(커밋 끝 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`). 편집 전 `git status`. 스펙·패치노트는 이미 고쳐져 있으니 건드리지 않는다.

## Task 1 — PullBadge 꺼내기 + 업무 모드 PullRow 목록

파일: `Sources/YugiTokenBar/UI/PackOpenView.swift` 하나.

1. `FlipCard`의 배지(NEW·+ⓒ·✕ 안 팔기)를 새 `struct PullBadge: View`로 옮긴다. 동작·문구·색·`.help`·`hoverSold`는 그대로, 바깥 `.padding(4)`만 tag 에서 빼서 `FlipCard` 쪽 호출에 붙인다:
   ```swift
   /// 개봉 카드의 NEW·자동 판매(+ⓒ) 배지. 판매 배지에 마우스를 올리면 ✕ 로 바뀌고, 누르면 판매를 취소한다
   struct PullBadge: View {
       let pull: Pull
       var canUnsell = false
       var onUnsell: (() -> Void)?
       @State private var hoverSold = false

       var body: some View {
           if pull.isNew { tag("NEW", Palette.badgeNew) }
           else if let coins = pull.soldFor {
               Button { onUnsell?() } label: {
                   tag(hoverSold && canUnsell ? "✕ 안 팔기" : "+\(coinText(coins))", hoverSold && canUnsell ? Palette.badgeLoss : Palette.badgeGain)
               }
               .buttonStyle(.plain)
               .disabled(!canUnsell)
               .onHover { hoverSold = $0 }
               .help(canUnsell ? "판매 취소: 코인을 돌려주고 카드를 가져요" : "코인이 모자라 취소할 수 없어요")
           }
       }

       private func tag(_ text: LocalizedStringKey, _ color: Color) -> some View {
           Text(text)
               .font(.system(size: 10, weight: .bold))
               .foregroundStyle(.white)
               .padding(.horizontal, 6)
               .padding(.vertical, 2)
               .background(color, in: Capsule())
       }
   }
   ```
   `FlipCard`: `.overlay(alignment: .topTrailing) { PullBadge(pull: pull, canUnsell: canUnsell, onUnsell: onUnsell).padding(4) }`, `hoverSold`·`tag` 삭제, `/// 자동 판매 표시…` 주석은 `onUnsell` 위에 "배지의 판매 취소" 정도로 짧게 남긴다.

2. `OpeningView`에 `@Environment(\.workMode) private var workMode`. body 의 카드 격자 `VStack(spacing: 10) { … }.frame(maxWidth: .infinity).onGeometryChange(…)`와 그 아래 `if !packLayout { Spacer(minLength: 0) }`를 이렇게 감싼다(격자 쪽 코드는 그대로):
   ```swift
   if workMode {
       VStack(spacing: 6) {
           ForEach(pulls.indices, id: \.self) { i in row(pulls[i], i) }
       }
       Spacer(minLength: 0)
   } else {
       …기존 격자 VStack…
       if !packLayout { Spacer(minLength: 0) }
   }
   ```
   (`let packLayout`… 계산 줄들은 if 밖에 그대로 두어도 된다.)

3. `OpeningView`에 줄 함수와 종류 함수:
   ```swift
   /// 업무 모드 개봉 줄: 배지 칸(폭 고정) · 등급 · 이름 · 오른쪽 끝 흐린 종류. 누르기 전엔 "눌러서 공개"만
   private func row(_ pull: Pull, _ i: Int) -> some View {
       let card = model.db.cards[pull.cid]
       return HStack(spacing: 8) {
           if flipped.contains(i) {
               PullBadge(pull: pull, canUnsell: model.game.state.coins >= (pull.soldFor ?? 0)) { model.keepSold(at: i) }
                   .frame(width: Self.badgeWidth, alignment: .leading)
               RarityPill(label: pull.label, size: 10)
               Text(card?.name ?? "").lineLimit(1)
               Spacer(minLength: 8)
               Text(kind(card)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
           } else {
               Text("눌러서 공개").foregroundStyle(.tertiary)
               Spacer(minLength: 0)
           }
       }
       .font(.callout)
       .padding(.horizontal, 10)
       .frame(height: 30)
       .background(.fill.tertiary, in: .rect(cornerRadius: 6))
       .contentShape(.rect)
       .onTapGesture { withAnimation(flip) { _ = flipped.insert(i) } }
       .accessibilityElement(children: .ignore)
       .accessibilityLabel(accessibilityLabel(pull, i))
       .accessibilityAddTraits(flipped.contains(i) ? [] : .isButton)
       .accessibilityAction { withAnimation(flip) { _ = flipped.insert(i) } }
       .accessibilityActions {
           if flipped.contains(i), pull.soldFor != nil { Button("판매 취소") { model.keepSold(at: i) } }
       }
   }

   /// 배지 칸 폭: 가장 넓은 "✕ 売らない" 58pt 가 들어간다
   private static let badgeWidth: CGFloat = 60

   /// 몬스터는 "드래곤족/일반", 마법·함정은 "마법 · 장착"
   private func kind(_ card: CardInfo?) -> String {
       guard let card else { return "" }
       return card.kindCode != nil ? [card.attr, card.type].compactMap { $0 }.joined(separator: " · ") : card.type ?? ""
   }
   ```

4. 새 문구 "눌러서 공개": `python3 tools/sync-strings.py` 로 키를 더하고 en "Click to reveal", ja "クリックして表示" 로 번역. `python3 tools/sync-strings.py --check`·`swift build`·`swift test` 통과. 커밋 1개(`feat: list pulls as rows in work mode`).
