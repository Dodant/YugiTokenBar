# 업무 모드 상점 줄 정돈: 막대 통일·숫자 오른쪽·호버 블러 (2026-10-12)

기준: 스펙 6절 "상점"의 업무 모드 문장. 브랜치 `feat/work-mode` 위에 이어서. 규칙은 `CLAUDE.md`(커밋 끝 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`). 편집 전 `git status`.

## Task 1 — ShopRow 아래 줄과 호버 블러

- `Sources/YugiTokenBar/UI/ShopView.swift`의 `private struct ShopRow`만 고친다.
  - 아래 줄 `HStack`을 `HStack(spacing: 8) { TintBar(value: Double(p.owned) / Double(max(p.total, 1)), tint: p.complete ? .green : .accentColor); Text(p.complete ? "완료 · \(p.owned)/\(p.total)" : "\(p.owned)/\(p.total)").font(.caption2).foregroundStyle(.secondary).monospacedDigit().lineLimit(1).frame(width: Self.countWidth, alignment: .trailing) }`로. `private static let countWidth: CGFloat = 110`(주석: 가장 긴 ja "コンプリート · 136/136"이 들어가는 폭. 숫자 칸을 고정해 모든 줄의 막대 길이를 같게). "융합 N장 남음" 분기는 뺀다.
  - 이름·아래 줄을 담은 `VStack`에 `.blur(radius: hovered ? 6 : 0)`을 건다(`.frame(maxWidth: .infinity, alignment: .leading)` 다음, `.overlay` 앞). 오버레이 버튼은 블러 밖(위)에 그려진다. 기존 `.animation(.easeOut(duration: 0.15), value: hovered)`가 블러도 같이 페이드한다.
  - doc comment: "업무 모드 상점 줄: 이름 · 왼쪽부터 진행 막대, 오른쪽 벽에 보유/전체. 마우스를 올리면 흐려지고 오른쪽에 작은 구매 버튼이 얹혀 뜬다 (봉투 자리 없음)".
- 새 문구 없음(`"완료 · %lld/%lld"`는 기존 키, `"\(p.owned)/\(p.total)"`은 한글 없음). `"%lld/%lld · 융합 %lld장 남음"` 키는 `PackRow`가 계속 쓴다. `python3 tools/sync-strings.py --check` 통과, `swift build`·`swift test` 통과. 스펙·패치노트는 건드리지 않는다. 커밋 1개.
