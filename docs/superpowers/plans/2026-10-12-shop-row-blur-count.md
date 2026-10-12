# 업무 모드 상점 줄: 블러는 버튼 뒤 숫자 칸만 (2026-10-12)

기준: 스펙 6절 "상점"의 업무 모드 문장. 브랜치 `feat/work-mode` 위에 이어서. 규칙은 `CLAUDE.md`(커밋 끝 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`). 편집 전 `git status`.

## Task 1 — ShopRow 블러를 숫자 Text로 옮기기

- `Sources/YugiTokenBar/UI/ShopView.swift`의 `private struct ShopRow`만 고친다.
  - 내용 `VStack`에 걸린 `.blur(radius: hovered ? 6 : 0)` 줄을 지운다.
  - 숫자 `Text(p.complete ? "완료 · …" : "…")`의 modifier 사슬 끝(`.frame(width: Self.countWidth, alignment: .trailing)` 다음)에 `.blur(radius: hovered ? 6 : 0)`을 건다. 이름·막대는 흐려지지 않는다. 기존 `.animation(.easeOut(duration: 0.15), value: hovered)`가 그대로 페이드한다.
  - doc comment를 "업무 모드 상점 줄: 이름 · 왼쪽부터 진행 막대, 오른쪽 벽에 보유/전체. 마우스를 올리면 오른쪽에 작은 구매 버튼이 얹혀 뜨고 그 뒤 숫자만 흐려진다 (봉투 자리 없음)"로.
- 새 문구 없음. `python3 tools/sync-strings.py --check`·`swift build`·`swift test` 통과. 스펙·패치노트는 건드리지 않는다. 커밋 1개.
