# 상점 줄 목록을 업무 모드 전용으로 (2026-10-12)

기준: 스펙 6절 "상점"(업무 모드 문장)과 "외관 > 업무 모드". 브랜치 `feat/work-mode` 위에 이어서. 앞선 플랜 `2026-10-12-shop-list.md`(상점 전체를 줄 목록으로)는 이 플랜으로 뒤집힌다: 업무 모드가 아니면 예전 3열 그리드 그대로, 업무 모드에서만 봉투 자리 없는 줄 목록.
규칙은 `CLAUDE.md`(색은 시스템 색 먼저, 문구는 한국어 리터럴 + `tools/sync-strings.py`, 커밋 끝 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`). 편집 전 `git status`.

## Task 1 — 그리드 복구 + 업무 모드 줄 목록

- 복구(새로 쓰지 말고 git 에서 되살린다. 커밋 `18ae983`이 상점 리스트 직전 상태):
  - `git checkout 18ae983 -- Sources/YugiTokenBar/UI/CardImageView.swift Resources/en.lproj/Localizable.strings Resources/ja.lproj/Localizable.strings` → `Palette.stampComplete`·`stampFusion`과 문구 키 3개("융합 %lld장 남음"·"다 모은 팩"·"남은 카드는 융합으로만 얻는 팩")가 돌아온다.
  - `git checkout 18ae983 -- Sources/YugiTokenBar/UI/ShopView.swift` → `PackTile`·`PackStamp`·3열 `LazyVGrid`가 돌아온다(이 시점엔 `ShopRow`가 없다).
- `Sources/YugiTokenBar/UI/ShopView.swift`에 다시 넣기:
  - `EraSection`에 `@Environment(\.workMode) private var workMode`. `if expanded { … }` 안을 `if workMode { LazyVStack(spacing: 6) { ForEach(packs, id: \.self) { ShopRow(index: $0) } } } else { 기존 LazyVGrid }`로. `.transition(.opacity)`는 둘 다에.
  - `private struct ShopRow: View` — `git show 187bec9:Sources/YugiTokenBar/UI/ShopView.swift`의 `ShopRow`에서 `PackImageView(...).frame(height: 36)` 줄만 뺀 것: `HStack(spacing: 8)` { `VStack(alignment: .leading, spacing: 3)` { `Text(pack.name).font(.callout).lineLimit(1)`; `HStack { TintBar(value: Double(p.owned) / Double(max(p.total, 1)), tint: p.complete ? .green : .accentColor); Text(p.fusionLeft > 0 ? "\(p.owned)/\(p.total) · 융합 \(p.fusionLeft)장 남음" : p.complete ? "완료 · \(p.owned)/\(p.total)" : "\(p.owned)/\(p.total)").font(.caption2).foregroundStyle(.secondary).monospacedDigit() }` } · `Spacer(minLength: 4)` · `BuyButton(index: index, cleared: p.cleared).controlSize(.small)` }. doc comment 한 줄 "업무 모드 상점 줄: 이름 · 진행 막대와 보유/전체 · 작은 구매 버튼 (봉투 자리 없음)".
- 문구: 새 키는 없어야 한다(세 리터럴 모두 기존 키). `python3 tools/sync-strings.py --check` 통과.
- 패치노트 `CHANGELOG.md`·`CHANGELOG.en.md`·`CHANGELOG.ja.md`의 `## 0.5.7 — 2026-10-12` 항목: `**🎨 개선**`(en `**🎨 Improvements**`, ja `**🎨 改善**`) 줄과 그 "상점을 3열 그리드에서 줄 목록으로…" 항목(과 그 앞 빈 줄)을 지우고, `**✨ …**` 블록의 업무 모드 항목 끝에 한 문장을 덧붙인다: ko "상점은 이미지 없는 줄 목록으로 보입니다." en "The shop shows a plain list of rows without images." ja "ショップは画像のない行リストで表示されます。" 제목 줄은 손대지 않는다.
- 스펙은 이미 고쳐져 있다(건드리지 않는다). `swift build`·`swift test` 통과. 커밋 1개.
