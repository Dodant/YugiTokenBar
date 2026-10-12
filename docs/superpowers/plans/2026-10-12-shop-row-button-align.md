# 업무 모드 상점 줄: 구매 버튼 아랫선을 막대 아랫선에 (2026-10-12)

기준: 스펙 6절 "상점"의 업무 모드 문장. 브랜치 `feat/work-mode` 위에 이어서. 규칙은 `CLAUDE.md`(커밋 끝 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`). 편집 전 `git status`.

## Task 1 — barBottom 커스텀 세로 정렬

- `Sources/YugiTokenBar/UI/ShopView.swift`
  - `ShopRow` 바로 위에 추가:
    ```swift
    extension VerticalAlignment {
        /// 업무 모드 상점 줄: 구매 버튼 아랫선을 진행 막대 아랫선에 맞추는 기준. TintBar 가 올려 보내고 오버레이가 받는다
        private enum BarBottom: AlignmentID {
            static func defaultValue(in d: ViewDimensions) -> CGFloat { d[.bottom] }
        }
        static let barBottom = VerticalAlignment(BarBottom.self)
    }
    ```
  - `ShopRow` 안 `TintBar(...)`에 `.alignmentGuide(.barBottom) { $0[.bottom] }`를 건다(명시한 값은 HStack·VStack 을 타고 올라간다).
  - `.overlay(alignment: .trailing)`을 `.overlay(alignment: Alignment(horizontal: .trailing, vertical: .barBottom))`로. 버튼 쪽은 기본값(`d[.bottom]`)이라 손대지 않는다.
  - doc comment 끝 "(봉투 자리 없음)" 앞에 "버튼 아랫선은 막대 아랫선에 맞춘다." 추가.
- 새 문구 없음. `python3 tools/sync-strings.py --check`·`swift build`·`swift test` 통과. 스펙·패치노트는 건드리지 않는다. 커밋 1개.
