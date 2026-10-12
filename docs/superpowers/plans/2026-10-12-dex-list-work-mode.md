# 업무 모드 컬렉션 줄 목록 + 정보 패널 실제 그림 (2026-10-12)

기준: 스펙 6절 외관의 업무 모드 문장("예외는 컬렉션 오른쪽 정보 패널…", "컬렉션 창도 카드 격자 대신…"). 브랜치 `feat/work-mode` 위에 이어서. 규칙은 `CLAUDE.md`(커밋 끝 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`). 편집 전 `git status`. 스펙·패치노트는 이미 고쳐져 있으니 건드리지 않는다. 새 문구 없음.

## Task 1 — 정보 패널만 업무 모드에서도 실제 그림

1. `Sources/YugiTokenBar/ImageCache.swift`
   - `func image(_ imageId: Int, size: Size, force: Bool = false) async -> NSImage?` — 두 `image(key:url:maxPixels:)` 호출에 `force: force`를 넘긴다.
   - `func cached(_ imageId: Int, size: Size, force: Bool = false) -> NSImage?` — `guard force || !workMode else { return nil }`.
   - `private func image(key: String, url: URL, maxPixels: Int? = nil, force: Bool = false)` — `guard force || !workMode else { return nil }`.
   - `force` 를 처음 쓰는 `image` 위 doc 에 한 줄: "force: 업무 모드여도 불러온다 (컬렉션 정보 패널의 고른 카드 한 장만)". `packImage`·`cachedPack` 은 그대로.
2. `Sources/YugiTokenBar/UI/CardImageView.swift` `CardImageView`
   - 속성 `var showInWorkMode = false` (doc: "업무 모드여도 실제 그림 (컬렉션 정보 패널)"), init 에 `showInWorkMode: Bool = false` 마지막 인자로 받아 저장, 초기 `cached(…, size: size, force: showInWorkMode)`.
   - `private var hidden: Bool { workMode && !showInWorkMode }` 를 두고 body 의 `if workMode` → `if hidden`, `.task(id: hidden ? nil : cid)`, `guard !hidden`, 안의 `cached`·`image` 호출에 `force: showInWorkMode`. 주석 "업무 모드면 nil" 은 "숨길 때는 nil" 로.
3. `Sources/YugiTokenBar/UI/CardDetailView.swift`: 맨 위 `CardImageView(db: model.db, cid: cid, size: .full)` → `CardImageView(db: model.db, cid: cid, size: .full, showInWorkMode: true)`, 위 주석 끝에 "업무 모드여도 실제 그림" 덧붙임.
4. `Tests/YugiTokenBarTests/ImageCacheTests.swift` `workModeSkipsLoading`: `cachedPack` 기대 줄 다음, `d.set(false…)` 앞에 넣는다:
   ```swift
   #expect(await cache.image(1, size: .small, force: true) != nil)
   #expect(await calls.value == 1)
   #expect(cache.cached(1, size: .small, force: true) != nil)
   #expect(cache.cached(1, size: .small) == nil)
   ```
   그 뒤 기존 끝 두 줄(`image != nil`, `calls.value == 1`)은 메모리 캐시라 그대로 맞는다. doc 줄에 "force 면 켜져 있어도 불러온다" 덧붙임.
- `swift build`·`swift test`. 커밋 1개(`feat: show the real card picture in the collection info panel in work mode`).

## Task 2 — 컬렉션 격자 → 줄 목록 (업무 모드)

`Sources/YugiTokenBar/UI/DexView.swift` 하나.

1. body 의 `LazyVGrid(columns: …, spacing: 14) { ForEach(entries) { … } }` 를 감싼다 (뒤 `.padding(16)` 이하 수식어는 그대로 `Group` 에 붙는다):
   ```swift
   Group {
       if workMode {
           LazyVStack(spacing: 2) {
               ForEach(entries) { entry in cell(cid: entry.cid, label: entry.label) }
           }
       } else {
           LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 12)], spacing: 14) {
               ForEach(entries) { entry in
                   cell(cid: entry.cid, label: entry.label)
               }
           }
       }
   }
   ```
2. `cell(cid:label:)`: `Hovering { hovered in VStack(spacing: 4) { … } .contentShape(Rectangle()) }` 의 VStack 을 업무 모드 갈래와 나눈다. 탭·접근성·draggable·contextMenu·onGeometryChange 등 바깥 수식어는 그대로 둘 다에 걸린다:
   ```swift
   return Hovering { hovered in Group {
       if workMode {
           // 업무 모드 줄: 등급 · 이름 · 오른쪽에 (마우스를 올리면) − · ☆ · ×n. 고르면 강조색 배경
           HStack(spacing: 8) {
               RarityPill(label: label, owned: owned, size: 10)
               MarqueeText(text: model.db.cards[cid]?.name ?? "", active: hovered)
                   .foregroundStyle(owned ? .primary : .secondary)
               Spacer(minLength: 0)
               if let deckID, hovered { minus(deckID, cid) }
               star(cid, hovered: hovered)
               if n > 1 || inDeck != nil { Text("×\(n)").fontWeight(.semibold).monospacedDigit() }
           }
           .font(.callout)
           .padding(.horizontal, 8)
           .frame(height: 28)
           .background(selected ? Color.accentColor.opacity(0.2) : .clear, in: .rect(cornerRadius: 6))
       } else {
           VStack(spacing: 4) { …기존 그대로… }
       }
   }
   .contentShape(Rectangle()) }
   ```
- `swift build`·`swift test`·`python3 tools/sync-strings.py --check`. 커밋 1개(`feat: list the collection as rows in work mode`).
