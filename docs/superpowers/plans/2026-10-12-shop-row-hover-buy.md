# 업무 모드 상점 줄: 구매 버튼은 마우스 올림에만 (2026-10-12)

기준: 스펙 6절 "상점"의 업무 모드 문장. 브랜치 `feat/work-mode` 위에 이어서. 규칙은 `CLAUDE.md`(커밋 끝 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`). 편집 전 `git status`.

## Task 1 — ShopRow 구매 버튼을 호버 오버레이로

- `Sources/YugiTokenBar/UI/ShopView.swift`의 `private struct ShopRow`만 고친다.
  - 몸체를 `Hovering { hovered in … }`(`DexView.swift`의 공용 헬퍼, `PackOpenView`도 씀)로 감싼다.
  - 줄 내용은 기존 `VStack(alignment: .leading, spacing: 3)`(이름 · `HStack { TintBar; 숫자 Text }`)만 남기고 `.frame(maxWidth: .infinity, alignment: .leading)`. 바깥 `HStack`·`Spacer(minLength: 4)`·레이아웃 안의 `BuyButton`은 뺀다.
  - 그 위에 `.overlay(alignment: .trailing) { if hovered { BuyButton(index: index, cleared: p.cleared).controlSize(.small).transition(.opacity) } }`.
  - 페이드: `Hovering`은 애니메이션을 걸지 않으므로 `.animation(.easeOut(duration: 0.15), value: hovered)`를 overlay 뒤에 건다(`PackTile`의 `withAnimation(.easeOut(duration: 0.15))`와 같은 길이). `lessMotion`은 보지 않는다(그리드 오버레이도 안 본다).
  - doc comment를 "업무 모드 상점 줄: 이름 · 진행 막대와 보유/전체. 마우스를 올리면 오른쪽에 작은 구매 버튼이 얹혀 뜬다 (봉투 자리 없음)"로.
- 새 문구 없음. `python3 tools/sync-strings.py --check` 통과, `swift build`·`swift test` 통과. 패치노트·스펙은 건드리지 않는다(스펙은 이미 고침). 커밋 1개.
