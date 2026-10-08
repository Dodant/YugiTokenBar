# YugiTokenBar Implementation Plan

> 역사 기록이고 현재 기준은 스펙(`docs/superpowers/specs/2026-10-01-yugitokenbar-design.md`)이다.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 토큰 사용량으로 코인과 무료 카드를 적립하고, 싱크로 이전 한국 정발 부스터 27팩을 열어 2,270종 도감을 채우는 macOS 메뉴바 앱.

**Architecture:** SwiftPM 실행 타깃 하나, 외부 의존성 없음. 순수 로직(`Game`/`GameState`/`CardDB`)과 SwiftUI 화면을 분리한다. 토큰 읽기는 PokeTokenBar(MIT) `LocalUsageReader`를 커밋 `de617e3`에서 복사해 쓴다. 카드 데이터는 Python 스크립트로 한 번 만들어 `Resources/cards.json`으로 커밋한다.

**Tech Stack:** Swift 6.4 / SwiftUI `MenuBarExtra(.window)` / Swift Testing / Python 3 표준 라이브러리 (데이터 스크립트)

**Spec:** `docs/superpowers/specs/2026-10-01-yugitokenbar-design.md`

> 이 계획의 모든 코드는 작성 시점(2026-10-01)에 scratch 패키지에서 실제로 빌드하고 테스트했다. 작업 단계별 중간 상태(작업 4 / 5 / 7)도 따로 빌드와 테스트를 통과했다.

## Global Constraints

- 저장소 루트: `~/Documents/YugiTokenBar`. 모든 경로는 이 기준.
- Swift tools 6.0, `platforms: [.macOS(.v14)]`, 외부 패키지 의존성 0.
- 카드 풀: 한국 정발 `【정규 부스터 팩】`, 발매일 < `2008/10/07`, 27팩, 고유 2,270종.
- 밸런스: `tokensPerCoin = 10_000`, `packPrice = 1_000`, `tokensPerFreeCard = 10_000_000`, `maxCopies = 2`, `unlockRatio = 0.5`, 5번째 장 R 70% / SR 18% / UR 9% / 최상위 3%.
- 토큰 = input + output + cacheWrite + cacheRead. provider는 `claude_code`, `codex`.
- 세이브: `~/Library/Application Support/YugiTokenBar/state.json` (+ `.bak`). 개발과 QA 때는 `YTB_STATE_DIR`로 반드시 분리하고 실제 세이브는 건드리지 않는다.
- 이미지: `https://images.ygoprodeck.com/images/{cards_small|cards}/<imageId>.jpg`, 캐시 `~/Library/Caches/YugiTokenBar/`. 번들에 넣지 않는다.
- UI 문구는 한국어.
- 커밋 메시지 끝: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`

## Review Focus

1. **로그를 일시적으로 0이나 작은 값으로 읽은 뒤 회복** → 같은 토큰을 두 번 적립하면 안 된다. 원장은 같은 날 안에서 내려가지 않는다 (작업 4 `transientLowReadingNeverDoubleCredits`).
2. **앱이 며칠 꺼져 있다가 켜짐** → 새 날짜의 누적치만 적립하고, 지난날 원장이 섞이지 않는다 (작업 4 `newDayStartsLedgerFromZero`).
3. **옛 버전 세이브(키 누락)나 손상된 세이브** → 초기화로 데이터를 잃으면 안 된다. 빠진 키는 기본값을 쓰고, 손상된 원본은 따로 보관한 뒤 `.bak`에서 복구한다 (작업 3).
4. **5팩 구매 중 팩이 완료됨** → 남은 팩은 열지 않고 코인도 깎지 않는다 (작업 5 `multiBuyStopsWhenPackCompletesAndKeepsCoins`).
5. **오래 쌓인 큰 적립(수십억 토큰) + 도감 완성 상태** → 무한 루프나 크래시 없이 게이지만 소모된다 (작업 4 `hugeCreditWithFullCollectionDoesNotHang`).

---

## File Structure

```
Package.swift
.gitignore
Resources/cards.json                     카드 데이터 (tools/build-cards.py 산출물, 커밋)
tools/build-cards.py                     Konami 한국 DB + YGOPRODeck → cards.json
tools/import-usage.sh                    PokeTokenBar 토큰 읽기 코드 복사 + 패치
scripts/build-app.sh                     .app 번들 + ad-hoc 서명 (+ --install)
Sources/YugiTokenBar/
  App.swift                              @main, MenuBarExtra + 창 2개
  AppModel.swift                         @MainActor 상태 홀더: 60초 갱신, 구매, 저장
  CardDB.swift                           cards.json 모델/로딩
  GameState.swift                        세이브 모델 + StateStore(.bak, 손상 보관)
  Game.swift                             Balance 상수, 적립, 뽑기, 구매, 해금 (순수 로직)
  ImageCache.swift                       이미지 디스크 + 메모리 캐시
  Usage/                                 PokeTokenBar 복사본 11개 + Shims.swift + TodayUsage.swift + NOTICE.md
  UI/CardImageView.swift                 카드 이미지 / 뒷면 / 실루엣
  UI/PopoverView.swift                   요약 팝오버
  UI/ShopView.swift                      상점 + PackRow
  UI/PackOpenView.swift                  팩 개봉 창 (뒤집기)
  UI/DexView.swift                       도감 창
Tests/YugiTokenBarTests/
  TestSupport.swift  UsageTests.swift  CardDBTests.swift  StateStoreTests.swift
  ClaimTests.swift   DrawTests.swift   ImageCacheTests.swift
```

---

### Task 1: 패키지 뼈대 + 토큰 읽기 코드 이식

**Files:**
- Create: `Package.swift`, `tools/import-usage.sh`, `Sources/YugiTokenBar/Usage/Shims.swift`, `Sources/YugiTokenBar/Usage/TodayUsage.swift`, `Sources/YugiTokenBar/Usage/NOTICE.md`, `Sources/YugiTokenBar/App.swift`(임시)
- Create (스크립트가 생성): `Sources/YugiTokenBar/Usage/{LocalUsageReader,AppLog,AppEnv,BinaryLocator,ClaudeAccountRoots,CustomScanRoots,Models,ModelPricing,UsageEnvironment,LogRepeatSuppressor,UsageCost}.swift`
- Modify: `.gitignore`
- Test: `Tests/YugiTokenBarTests/TestSupport.swift`, `Tests/YugiTokenBarTests/UsageTests.swift`

**Interfaces:**
- Produces: `TodayUsage.read(now:) -> (date: String, byProvider: [String: Int])`, `TodayUsage.total(_ entries: [LocalUsageReader.Entry], day: String) -> Int`, `AppLog.write(_:)`, 테스트 헬퍼 `SeededRNG(seed:)`, `makeDB(_:)`, `tempDir()`

- [ ] **Step 1: `.gitignore`에 빌드 산출물 추가**

```
.superpowers/
.build/
.DS_Store
build/
qa-state/
```

- [ ] **Step 2: `Package.swift` 작성**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "YugiTokenBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "YugiTokenBar",
            path: "Sources/YugiTokenBar",
            exclude: ["Usage/NOTICE.md"]
        ),
        .testTarget(
            name: "YugiTokenBarTests",
            dependencies: ["YugiTokenBar"],
            path: "Tests/YugiTokenBarTests"
        ),
    ]
)
```

- [ ] **Step 3: `tools/import-usage.sh` 작성 후 실행**

PokeTokenBar 저장소(`~/remote-claude-projects/code/PokeTokenBar-carryover`)의 커밋 `de617e3`에서 11개 파일을 복사하고, 이 앱에 없는 의존성 3곳을 패치한다. 패치할 대상을 못 찾으면 `assert`로 실패한다.

```bash
#!/bin/bash
# PokeTokenBar(MIT) 토큰 읽기 코드를 고정 커밋에서 복사하고, 이 앱에 없는 의존성을 패치한다.
# 저장소 루트에서 실행: bash tools/import-usage.sh
set -euo pipefail
SRC=${PTB_REPO:-$HOME/remote-claude-projects/code/PokeTokenBar-carryover}
REV=de617e3
DST=Sources/YugiTokenBar/Usage
mkdir -p "$DST"
for f in LocalUsageReader AppLog AppEnv BinaryLocator ClaudeAccountRoots CustomScanRoots Models ModelPricing UsageEnvironment LogRepeatSuppressor UsageCost; do
  git -C "$SRC" show "$REV:Sources/PokeTokenBar/Core/$f.swift" > "$DST/$f.swift"
done
python3 - "$DST" <<'PY'
import re, sys
d = sys.argv[1]
def edit(name, fn):
    p = f"{d}/{name}.swift"; s = open(p).read(); t = fn(s)
    assert t != s, f"{name}: 패치 대상 없음"
    open(p, "w").write(t)
# UI 문자열(L) 의존 메서드 제거
edit("UsageCost", lambda s: re.sub(r"\n    func text\(_ l: L.*?\n    }\n\n    func explanation\(_ l: L\).*?\n    }\n", "\n", s, flags=re.S))
# 설정 화면용 추가 provider 루트 제거 (이 앱은 해당 리더를 복사하지 않음)
edit("CustomScanRoots", lambda s: re.sub(r'        case "antigravity":.*?(?=        case "pi":)', "", s, flags=re.S))
edit("AppLog", lambda s: s.replace("PokeTokenBar.log", "YugiTokenBar.log").replace('"poketokenbar.log"', '"yugitokenbar.log"'))
PY
```

Run: `bash tools/import-usage.sh && ls Sources/YugiTokenBar/Usage | wc -l`
Expected: `11`

- [ ] **Step 4: `Shims.swift`, `TodayUsage.swift`, `NOTICE.md`, 임시 `App.swift` 작성**

`Sources/YugiTokenBar/Usage/Shims.swift`:
```swift
// ponytail: PokeTokenBar OAuthLimitsProvider.swift 에서 ClaudeAccountRoots 가 쓰는 두 선언만 발췌
struct AccountIdentity: Equatable, Sendable {
    let email: String
    let organizationName: String?
}

enum OAuthCredentialData {
    static let claudeKeychainService = "Claude Code-credentials"
}
```

`Sources/YugiTokenBar/Usage/TodayUsage.swift`:
```swift
import Foundation

/// 오늘(로컬 날짜) provider별 누적 토큰. 토큰 = input + output + cacheWrite + cacheRead (PokeTokenBar 와 동일).
enum TodayUsage {
    static func read(now: Date = Date()) -> (date: String, byProvider: [String: Int]) {
        let start = Calendar.current.startOfDay(for: now)
        let today = LocalUsageReader.localDayFormatter().string(from: now)
        return (today, [
            "claude_code": total(LocalUsageReader.claudeEntries(modifiedSince: start), day: today),
            "codex": total(LocalUsageReader.codexEntries(modifiedSince: start), day: today),
        ])
    }

    static func total(_ entries: [LocalUsageReader.Entry], day: String) -> Int {
        var sum = 0
        for e in entries where e.localDay == day {
            sum += e.input + e.output + e.cacheWrite + e.cacheRead
        }
        return sum
    }
}
```

`Sources/YugiTokenBar/Usage/NOTICE.md`:
```markdown
# Usage/ 출처

이 폴더의 다음 파일은 [PokeTokenBar](https://github.com/chattymin/PokeTokenBar) (MIT License, Copyright (c) 2026 chattymin)
로컬 브랜치 `graduation-carryover` 커밋 `de617e3`의 `Sources/PokeTokenBar/Core/`에서 `tools/import-usage.sh`로 복사했다.

LocalUsageReader, AppLog, AppEnv, BinaryLocator, ClaudeAccountRoots, CustomScanRoots, Models, ModelPricing,
UsageEnvironment, LogRepeatSuppressor, UsageCost

## 변경점
1. `UsageCost.swift`: UI 문자열 타입 `L`에 의존하는 `text(_:compact:)`, `explanation(_:)` 제거
2. `CustomScanRoots.swift`: `curatedRoots(for:)`에서 복사하지 않은 리더(antigravity, opencode, aside, hermes, cursor, copilot, kiro) case 제거
3. `AppLog.swift`: 로그 파일 `YugiTokenBar.log`, 큐 라벨 `yugitokenbar.log`
4. `Shims.swift`(신규): `OAuthLimitsProvider.swift`의 `AccountIdentity`, `OAuthCredentialData.claudeKeychainService`만 발췌
5. `TodayUsage.swift`(신규): 이 앱 전용 오늘 누적치 집계

## MIT License
Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
documentation files (the "Software"), to deal in the Software without restriction, including without limitation the
rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit
persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the
Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```

`Sources/YugiTokenBar/App.swift` (작업 7에서 교체):
```swift
import SwiftUI

@main
struct YugiTokenBarApp: App {
    var body: some Scene {
        MenuBarExtra("YugiTokenBar") { Text("준비 중") }
    }
}
```

- [ ] **Step 5: 테스트 헬퍼와 실패하는 사용량 테스트 작성**

`Tests/YugiTokenBarTests/TestSupport.swift`:
```swift
import Foundation
@testable import YugiTokenBar

/// 시드 고정 RNG (SplitMix64)
struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

func tempDir() -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ytb-test-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}
```

`Tests/YugiTokenBarTests/UsageTests.swift`:
```swift
import Foundation
import Testing
@testable import YugiTokenBar

@Suite struct UsageTests {
    @Test func claudeFixtureCountsAllFourBucketsOnce() throws {
        let root = tempDir()
        let project = root.appendingPathComponent("proj")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let ts = ISO8601DateFormatter().string(from: Date())
        let line = #"{"type":"assistant","timestamp":"\#(ts)","requestId":"req1","message":{"id":"msg1","model":"claude-opus-5-5","usage":{"input_tokens":100,"output_tokens":20,"cache_creation_input_tokens":3,"cache_read_input_tokens":4000}}}"#
        // 같은 메시지가 두 번 기록돼도 한 번만 센다
        try (line + "\n" + line + "\n").write(to: project.appendingPathComponent("s.jsonl"), atomically: true, encoding: .utf8)

        let entries = LocalUsageReader.claudeEntries(modifiedSince: Date().addingTimeInterval(-3600), roots: [root])
        let today = LocalUsageReader.localDayFormatter().string(from: Date())
        #expect(TodayUsage.total(entries, day: today) == 4123)
        #expect(TodayUsage.total(entries, day: "1999-01-01") == 0)
    }
}
```

- [ ] **Step 6: 테스트 실행**

Run: `swift test --filter UsageTests`
Expected: `Test run with 1 test in 1 suite passed`. 같은 메시지가 두 줄이어도 4123으로 한 번만 센다.

- [ ] **Step 7: 실제 로그 스모크 확인 (수동)**

Run: `swift run YugiTokenBar &` → 메뉴바에 "YugiTokenBar"가 뜨면 종료(`pkill -x YugiTokenBar`).

- [ ] **Step 8: Commit**

```bash
git add .gitignore Package.swift tools/import-usage.sh Sources Tests
git commit -m "feat: scaffold package and import PokeTokenBar usage reader

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: 카드 데이터 (스크립트 + cards.json + CardDB)

**Files:**
- Create: `tools/build-cards.py`, `Resources/cards.json`(생성물), `Sources/YugiTokenBar/CardDB.swift`
- Modify: `Tests/YugiTokenBarTests/TestSupport.swift` (`makeDB` 추가)
- Test: `Tests/YugiTokenBarTests/CardDBTests.swift`

**Interfaces:**
- Produces: `struct CardInfo { name, attr?, level?, type?, atk?, def?, text, imageId? }`, `struct PackCard { cid: Int, tier: Int, label: String }`, `struct Pack { pid, name, date, cards: [PackCard] }`, `struct CardDB { packs: [Pack]; cards: [Int: CardInfo]; allCIDs: [Int]; init(packs:cards:); static func load(from: URL) throws; static func bundled() throws; static let repoCardsURL }`
- cards.json 형식: `{"packs":[{"pid","name","date":"YYYY-MM-DD","cards":[{"cid","tier","label"}]}], "cards":{"<cid>":{name,attr,level,type,atk,def,text,imageId}}}`. tier는 N 1 · R 2 · SR 3 · UR 4 · SE/UL/HR 5.

- [ ] **Step 1: 실패하는 데이터 테스트 작성**

`Tests/YugiTokenBarTests/CardDBTests.swift`:
```swift
import Foundation
import Testing
@testable import YugiTokenBar

@Suite struct CardDBTests {
    @Test func bundledDataMatchesKoreanPreSynchroBoosters() throws {
        let db = try CardDB.load(from: CardDB.repoCardsURL)
        #expect(db.packs.count == 27)
        #expect(db.packs.first?.name == "푸른 눈의 백룡의 전설")
        #expect(db.packs.last?.name == "파괴의 빛")
        #expect(db.packs.allSatisfy { $0.date < "2008-10-07" })
        #expect(db.packs.map(\.date) == db.packs.map(\.date).sorted())
        #expect(db.allCIDs.count == 2270)
        for pack in db.packs {
            for card in pack.cards {
                #expect(db.cards[card.cid] != nil, "팩 \(pack.name) 의 cid \(card.cid) 가 cards 에 없음")
                #expect((1...5).contains(card.tier))
            }
        }
        #expect(db.cards.values.allSatisfy { !$0.name.isEmpty && $0.imageId != nil })
        #expect(db.cards[4007]?.name == "푸른 눈의 백룡")
        #expect(db.cards[4007]?.imageId == 89631139)
    }
}
```

Run: `swift test --filter CardDBTests`
Expected: 컴파일 실패 — `cannot find 'CardDB' in scope`

- [ ] **Step 2: `tools/build-cards.py` 작성**

Konami 페이지 구조 메모:
- 상품 목록 행: `<div class="time">YYYY/MM/DD</div>` … `<span class="ws_nowrap">【정규 부스터 팩】</span>` … `<p>팩명</p><input class="link_value" value="…pid=N…">`
- 팩 페이지 카드 행: `<div class="t_row …">` 안에 `class="cid" value=`, `lr_icon rid rid_N` + `<p>라벨</p>`, `card_name`, `box_card_attribute`, `box_card_level_rank`, `card_info_species_and_other_item`(몬스터) 또는 `box_card_effect`(마법·함정, 없으면 "일반"), `atk_power`, `def_power`, `box_card_text`
- 팩 페이지에는 카드 번호(LOB-K001 등)가 없다. 화면의 번호는 팩 안에서의 순서다.

```python
#!/usr/bin/env python3
"""Konami 한국 DB + YGOPRODeck → Resources/cards.json

한국 정발 정규 부스터 팩 중 『듀얼리스트의 태동』(2008-10-07, 첫 싱크로 팩) 이전만 수집한다.
사용: python3 tools/build-cards.py [출력경로]
"""
import html
import json
import re
import sys
import time
import urllib.request

TIER = {"N": 1, "R": 2, "SR": 3, "UR": 4}  # 그 외(SE 시크릿, UL 얼티미트, HR 홀로그래픽) = 5
BASE = "https://www.db.yugioh-card.com/yugiohdb/"
CUTOFF = "2008/10/07"
OUT = sys.argv[1] if len(sys.argv) > 1 else "Resources/cards.json"


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "YugiTokenBar card builder (personal use)"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read().decode("utf-8")


def clean(s):
    s = re.sub(r"<!--.*?-->", "", s, flags=re.S)
    s = re.sub(r"<br\s*/?>", "\n", s)
    s = re.sub(r"<[^>]+>", "", s)
    s = html.unescape(s)
    return "\n".join(" ".join(line.split()) for line in s.split("\n")).strip()


def first(pattern, text, default=None):
    m = re.search(pattern, text, re.S)
    return clean(m.group(1)) if m else default


def parse_products(page):
    rows = re.findall(
        r'<div class="time">\s*(\d{4}/\d\d/\d\d)\s*</div>.*?<span class="ws_nowrap">(【[^】]*】)</span>'
        r'.*?<p>([^<]*)</p>\s*<input type="hidden" class="link_value" value="[^"]*pid=(\d+)',
        page, re.S)
    boosters = [(d, html.unescape(n).strip(), pid) for d, cat, n, pid in rows
                if cat == "【정규 부스터 팩】" and d < CUTOFF]
    return sorted(boosters)


def parse_pack(page):
    cards = []
    seen = set()
    for row in re.split(r'<div class="t_row ', page)[1:]:
        cid = re.search(r'class="cid" value="(\d+)"', row)
        rid = re.search(r'lr_icon rid rid_(\d+)', row)
        if not cid or not rid:
            continue
        cid = int(cid.group(1))
        if cid in seen:
            continue
        seen.add(cid)
        label = first(r'lr_icon rid rid_\d+[^>]*>\s*<p>([^<]*)</p>', row)
        attr = first(r'box_card_attribute">.*?<span>([^<]*)</span>', row)
        kind = first(r'card_info_species_and_other_item"><span>(.*?)</span>', row)
        if kind:
            kind = kind.strip("[] \n").replace("\n", "").replace("／", "/")
        else:
            kind = first(r'box_card_effect">.*?<span>([^<]*)</span>', row, "일반")
        level = first(r'box_card_level_rank[^>]*>.*?<span>([^<]*)</span>', row)
        atk = first(r'class="atk_power">\s*<span>([^<]*)</span>', row)
        dfn = first(r'class="def_power"><span>(.*?)</span>', row)
        cards.append({
            "cid": cid,
            "label": label,
            "tier": TIER.get(label, 5),
            "info": {
                "name": first(r'<span class="card_name">(.*?)</span>', row),
                "attr": attr,
                "level": int(re.sub(r"\D", "", level)) if level else None,
                "type": kind,
                "atk": re.sub(r"[^\d?]", "", atk) if atk else None,
                "def": re.sub(r"[^\d?]", "", dfn) if dfn else None,
                "text": first(r'box_card_text[^"]*">(.*?)</dd>', row, ""),
            },
        })
    return cards


def main():
    products = parse_products(get(BASE + "card_list.action?request_locale=ko"))
    packs, infos = [], {}
    for date, name, pid in products:
        page = get(BASE + f"card_search.action?ope=1&sess=1&pid={pid}&rp=99999&request_locale=ko")
        cards = parse_pack(page)
        for c in cards:
            infos.setdefault(c["cid"], c["info"])
        packs.append({"pid": pid, "name": name, "date": date.replace("/", "-"),
                      "cards": [{"cid": c["cid"], "tier": c["tier"], "label": c["label"]} for c in cards]})
        dist = {}
        for c in cards:
            dist[c["label"]] = dist.get(c["label"], 0) + 1
        print(f"{date} {name}: {len(cards)} {dist}", flush=True)
        time.sleep(1)

    ygo = json.loads(get("https://db.ygoprodeck.com/api/v7/cardinfo.php?misc=yes"))["data"]
    by_konami = {}
    for c in ygo:
        for m in c.get("misc_info", []):
            if m.get("konami_id"):
                by_konami.setdefault(int(m["konami_id"]), c["card_images"][0]["id"])
    missing = []
    for cid, info in infos.items():
        info["imageId"] = by_konami.get(cid)
        if info["imageId"] is None:
            missing.append(f"{cid} {info['name']}")

    out = {"packs": packs, "cards": {str(k): v for k, v in sorted(infos.items())}}
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))
    print(f"packs={len(packs)} distinct={len(infos)} missingImages={len(missing)}")
    for m in missing:
        print("  no image:", m)
    if len(packs) != 27 or any(not i["name"] for i in infos.values()):
        sys.exit("검증 실패: 팩 수가 27이 아니거나 이름이 빈 카드가 있음")


if __name__ == "__main__":
    main()
```

- [ ] **Step 3: 스크립트 실행 (약 1분, Konami에 1초 간격으로 요청)**

Run: `mkdir -p Resources && python3 tools/build-cards.py`
Expected: 마지막 줄이 `packs=27 distinct=2270 missingImages=0`. 『푸른 눈의 백룡의 전설』 줄은 `126 {'SE': 2, 'UR': 10, …}`.

- [ ] **Step 4: `CardDB.swift` 작성 + TestSupport에 `makeDB` 추가**

`Sources/YugiTokenBar/CardDB.swift`:
```swift
import Foundation

struct CardInfo: Codable, Sendable, Equatable {
    let name: String
    let attr: String?
    let level: Int?
    let type: String?
    let atk: String?
    let def: String?
    let text: String
    let imageId: Int?
}

struct PackCard: Codable, Sendable, Equatable {
    let cid: Int
    /// 1 N · 2 R · 3 SR · 4 UR · 5 SE/UL/HR
    let tier: Int
    let label: String
}

struct Pack: Codable, Sendable, Identifiable, Equatable {
    let pid: String
    let name: String
    let date: String
    let cards: [PackCard]
    var id: String { pid }
}

/// cards.json (tools/build-cards.py 산출물). packs 는 발매일 오름차순 = 해금 순서.
struct CardDB: Sendable {
    let packs: [Pack]
    let cards: [Int: CardInfo]
    let allCIDs: [Int]

    init(packs: [Pack], cards: [Int: CardInfo]) {
        self.packs = packs
        self.cards = cards
        self.allCIDs = cards.keys.sorted()
    }

    static func load(from url: URL) throws -> CardDB {
        struct File: Decodable {
            let packs: [Pack]
            let cards: [String: CardInfo]
        }
        let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
        var cards: [Int: CardInfo] = [:]
        for (key, info) in file.cards {
            if let cid = Int(key) { cards[cid] = info }
        }
        return CardDB(packs: file.packs, cards: cards)
    }

    /// .app 안에서는 Contents/Resources/cards.json, `swift run`·테스트에서는 저장소의 Resources/cards.json.
    static func bundled() throws -> CardDB {
        if let url = Bundle.main.url(forResource: "cards", withExtension: "json") {
            return try load(from: url)
        }
        return try load(from: repoCardsURL)
    }

    static let repoCardsURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // Sources/YugiTokenBar
        .deletingLastPathComponent()  // Sources
        .deletingLastPathComponent()  // 저장소 루트
        .appendingPathComponent("Resources/cards.json")
}
```

`Tests/YugiTokenBarTests/TestSupport.swift`의 `func tempDir()` 위에 추가 (작업 4, 5 테스트가 사용):
```swift
/// 팩마다 (cid, tier) 목록으로 작은 카드 DB를 만든다.
func makeDB(_ packs: [[(cid: Int, tier: Int)]]) -> CardDB {
    var cards: [Int: CardInfo] = [:]
    var built: [Pack] = []
    for (i, list) in packs.enumerated() {
        for c in list {
            cards[c.cid] = CardInfo(name: "카드\(c.cid)", attr: nil, level: nil, type: nil,
                                    atk: nil, def: nil, text: "", imageId: nil)
        }
        built.append(Pack(pid: "p\(i)", name: "팩\(i)", date: "2004-01-01",
                          cards: list.map { PackCard(cid: $0.cid, tier: $0.tier, label: "T\($0.tier)") }))
    }
    return CardDB(packs: built, cards: cards)
}
```

- [ ] **Step 5: 테스트 통과 확인**

Run: `swift test`
Expected: `Test run with 2 tests in 2 suites passed`

- [ ] **Step 6: Commit**

```bash
git add tools/build-cards.py Resources/cards.json Sources/YugiTokenBar/CardDB.swift Tests
git commit -m "feat: add Korean pre-Synchro booster card data and CardDB

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: 세이브 (GameState + StateStore)

**Files:**
- Create: `Sources/YugiTokenBar/GameState.swift`
- Test: `Tests/YugiTokenBarTests/StateStoreTests.swift`

**Interfaces:**
- Consumes: `AppLog.write(_:)` (작업 1)
- Produces: `struct LogEntry { cid: Int; source: String; date: Date }`, `struct GameState { coins, coinRemainder, dropProgress: Int; owned: [Int: Int]; unlocked: Int; claimedDate: String?; claimedByProvider: [String: Int]; unseenFree: Int; log: [LogEntry] }` (Codable, 빠진 키는 기본값), `struct StateStore { url; backupURL; static func standard(); func load() -> GameState; func save(_:) throws }`
- JSON에서 `owned`는 `{"4007":2}` 형태다(Int 키 딕셔너리).

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/YugiTokenBarTests/StateStoreTests.swift`:
```swift
import Foundation
import Testing
@testable import YugiTokenBar

@Suite struct StateStoreTests {
    @Test func roundTrip() throws {
        let store = StateStore(url: tempDir().appendingPathComponent("state.json"))
        var state = GameState()
        state.coins = 42
        state.owned = [4007: 2, 4009: 1]
        state.claimedDate = "2026-10-01"
        state.claimedByProvider = ["codex": 5]
        state.log = [LogEntry(cid: 4007, source: "free", date: Date(timeIntervalSince1970: 1_000))]
        try store.save(state)
        #expect(store.load() == state)
    }

    @Test func olderSaveMissingKeysStillLoads() throws {
        let store = StateStore(url: tempDir().appendingPathComponent("state.json"))
        try Data(#"{"coins":7,"owned":{"4007":2}}"#.utf8).write(to: store.url)
        let state = store.load()
        #expect(state.coins == 7)
        #expect(state.owned == [4007: 2])
        #expect(state.unlocked == 1)
    }

    @Test func missingFileGivesFreshState() {
        let store = StateStore(url: tempDir().appendingPathComponent("state.json"))
        #expect(store.load() == GameState())
    }

    @Test func corruptFileRestoresBackupAndKeepsCorruptCopy() throws {
        let dir = tempDir()
        let store = StateStore(url: dir.appendingPathComponent("state.json"))
        var first = GameState()
        first.coins = 1
        try store.save(first)
        var second = GameState()
        second.coins = 2
        try store.save(second)  // .bak = first
        try Data("{깨짐".utf8).write(to: store.url)

        #expect(store.load().coins == 1)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(names.contains { $0.hasPrefix("state.corrupt-") })
    }
}
```

Run: `swift test --filter StateStoreTests`
Expected: 컴파일 실패 — `cannot find 'StateStore' in scope`

- [ ] **Step 2: `GameState.swift` 작성**

```swift
import Foundation

struct LogEntry: Codable, Sendable, Equatable {
    let cid: Int
    /// "free" 또는 팩 pid
    let source: String
    let date: Date
}

struct GameState: Codable, Sendable, Equatable {
    var coins = 0
    var coinRemainder = 0
    var dropProgress = 0
    var owned: [Int: Int] = [:]
    var unlocked = 1
    var claimedDate: String?
    var claimedByProvider: [String: Int] = [:]
    var unseenFree = 0
    var log: [LogEntry] = []

    init() {}

    /// 빠진 키는 기본값 — 나중에 필드를 추가해도 옛 세이브가 "손상"으로 초기화되지 않게.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GameState()
        coins = try c.decodeIfPresent(Int.self, forKey: .coins) ?? d.coins
        coinRemainder = try c.decodeIfPresent(Int.self, forKey: .coinRemainder) ?? d.coinRemainder
        dropProgress = try c.decodeIfPresent(Int.self, forKey: .dropProgress) ?? d.dropProgress
        owned = try c.decodeIfPresent([Int: Int].self, forKey: .owned) ?? d.owned
        unlocked = try c.decodeIfPresent(Int.self, forKey: .unlocked) ?? d.unlocked
        claimedDate = try c.decodeIfPresent(String.self, forKey: .claimedDate)
        claimedByProvider = try c.decodeIfPresent([String: Int].self, forKey: .claimedByProvider) ?? d.claimedByProvider
        unseenFree = try c.decodeIfPresent(Int.self, forKey: .unseenFree) ?? d.unseenFree
        log = try c.decodeIfPresent([LogEntry].self, forKey: .log) ?? d.log
    }
}

/// state.json 저장소. 원자적 쓰기, 쓰기 전 직전 파일을 .bak 으로 보존.
struct StateStore {
    let url: URL
    var backupURL: URL { url.appendingPathExtension("bak") }

    /// `YTB_STATE_DIR` 가 있으면 그 폴더를 쓴다(개발·QA 때 실제 세이브와 분리).
    static func standard() -> StateStore {
        let override = ProcessInfo.processInfo.environment["YTB_STATE_DIR"] ?? ""
        let dir = override.isEmpty
            ? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("YugiTokenBar")
            : URL(fileURLWithPath: override, isDirectory: true)
        return StateStore(url: dir.appendingPathComponent("state.json"))
    }

    func load() -> GameState {
        if let state = Self.decode(url) { return state }
        if FileManager.default.fileExists(atPath: url.path) {
            // 손상된 원본은 지우지 않고 옆에 보관한다(데이터 유실 방지).
            let aside = url.deletingLastPathComponent()
                .appendingPathComponent("state.corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: url, to: aside)
            AppLog.write("state.json 손상 → \(aside.lastPathComponent) 보관, .bak 복구 시도")
        }
        return Self.decode(backupURL) ?? GameState()
    }

    func save(_ state: GameState) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(state)
        if fm.fileExists(atPath: url.path) {
            try? fm.removeItem(at: backupURL)
            try fm.copyItem(at: url, to: backupURL)
        }
        try data.write(to: url, options: .atomic)
    }

    private static func decode(_ url: URL) -> GameState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(GameState.self, from: data)
    }
}
```

- [ ] **Step 3: 테스트 통과 확인**

Run: `swift test --filter StateStoreTests`
Expected: 4 tests passed (`roundTrip`, `olderSaveMissingKeysStillLoads`, `missingFileGivesFreshState`, `corruptFileRestoresBackupAndKeepsCorruptCopy`)

- [ ] **Step 4: Commit**

```bash
git add Sources/YugiTokenBar/GameState.swift Tests/YugiTokenBarTests/StateStoreTests.swift
git commit -m "feat: add save state with backup and corrupt-file preservation

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: 토큰 적립 (Game 핵심: 원장, 코인, 무료 카드, 해금)

**Files:**
- Create: `Sources/YugiTokenBar/Game.swift`
- Test: `Tests/YugiTokenBarTests/ClaimTests.swift`

**Interfaces:**
- Consumes: `CardDB`, `GameState`, `LogEntry`
- Produces: `enum Balance { tokensPerCoin, packPrice, tokensPerFreeCard, maxCopies, unlockRatio, slot5Weights: [(tier: Int, weight: Double)], logLimit }`, `struct Game { let db: CardDB; var state: GameState }`, 메서드: `mutating claim(today:byProvider:using:) -> [Int]`, `mutating credit(_:using:) -> [Int]`, `copies(_:) -> Int`, `ownedDistinct: Int`, `progress(_ pack: Int) -> (owned: Int, total: Int)`, `isUnlocked(_:) -> Bool`, `drawFree(using:) -> Int?`, `mutating give(_ cid: Int, source: String, now: Date = Date())`. RNG는 모두 `inout some RandomNumberGenerator` 제네릭이다.

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/YugiTokenBarTests/ClaimTests.swift`:
```swift
import Testing
@testable import YugiTokenBar

@Suite struct ClaimTests {
    let db = makeDB([[(1, 1), (2, 1)]])

    @Test func firstRunSeedsLedgerWithoutCredit() {
        var game = Game(db: db, state: GameState())
        var rng = SeededRNG(seed: 1)
        _ = game.claim(today: "2026-10-01", byProvider: ["claude_code": 50_000_000], using: &rng)
        #expect(game.state.coins == 0)
        #expect(game.state.dropProgress == 0)
        #expect(game.state.claimedByProvider == ["claude_code": 50_000_000])
    }

    @Test func sameTotalsTwiceCreditOnce() {
        var game = Game(db: db, state: GameState())
        var rng = SeededRNG(seed: 1)
        _ = game.claim(today: "2026-10-01", byProvider: ["claude_code": 0], using: &rng)
        _ = game.claim(today: "2026-10-01", byProvider: ["claude_code": 25_000, "codex": 5_000], using: &rng)
        _ = game.claim(today: "2026-10-01", byProvider: ["claude_code": 25_000, "codex": 5_000], using: &rng)
        #expect(game.state.coins == 3)
        #expect(game.state.dropProgress == 30_000)
    }

    @Test func transientLowReadingNeverDoubleCredits() {
        var game = Game(db: db, state: GameState())
        var rng = SeededRNG(seed: 1)
        _ = game.claim(today: "2026-10-01", byProvider: ["claude_code": 0], using: &rng)
        _ = game.claim(today: "2026-10-01", byProvider: ["claude_code": 100_000], using: &rng)
        _ = game.claim(today: "2026-10-01", byProvider: ["claude_code": 0], using: &rng)  // 로그 읽기 일시 실패
        _ = game.claim(today: "2026-10-01", byProvider: ["claude_code": 120_000], using: &rng)
        #expect(game.state.dropProgress == 120_000)
        #expect(game.state.claimedByProvider["claude_code"] == 120_000)
    }

    @Test func newDayStartsLedgerFromZero() {
        var game = Game(db: db, state: GameState())
        var rng = SeededRNG(seed: 1)
        _ = game.claim(today: "2026-10-01", byProvider: ["claude_code": 900_000], using: &rng)
        _ = game.claim(today: "2026-10-04", byProvider: ["claude_code": 40_000], using: &rng)  // 며칠 꺼져 있다 켜짐
        #expect(game.state.dropProgress == 40_000)
        #expect(game.state.claimedDate == "2026-10-04")
    }

    @Test func coinsAndFreeCardsCarryRemainders() {
        var game = Game(db: db, state: GameState())
        var rng = SeededRNG(seed: 1)
        let got = game.credit(10_005_000, using: &rng)
        #expect(game.state.coins == 1_000)
        #expect(game.state.coinRemainder == 5_000)
        #expect(got.count == 1)
        #expect(game.state.dropProgress == 5_000)
        #expect(game.state.unseenFree == 1)
        _ = game.credit(5_000, using: &rng)
        #expect(game.state.coins == 1_001)
        #expect(game.state.coinRemainder == 0)
    }

    @Test func hugeCreditWithFullCollectionDoesNotHang() {
        var state = GameState()
        state.owned = [1: 2, 2: 2]
        var game = Game(db: db, state: state)
        var rng = SeededRNG(seed: 1)
        let got = game.credit(5_000_000_000, using: &rng)  // 무료 카드 500장분
        #expect(got.isEmpty)
        #expect(game.state.dropProgress == 0)
        #expect(game.state.coins == 500_000)
    }
}
```

Run: `swift test --filter ClaimTests`
Expected: 컴파일 실패 — `cannot find 'Game' in scope`

- [ ] **Step 2: `Game.swift` 작성**

```swift
import Foundation

enum Balance {
    static let tokensPerCoin = 10_000
    static let packPrice = 1_000
    static let tokensPerFreeCard = 10_000_000
    static let maxCopies = 2
    static let unlockRatio = 0.5
    /// 팩 5번째 장의 티어 확률 (R / SR / UR / 최상위)
    static let slot5Weights: [(tier: Int, weight: Double)] = [(2, 0.70), (3, 0.18), (4, 0.09), (5, 0.03)]
    static let logLimit = 50
}

struct Game: Sendable {
    let db: CardDB
    var state: GameState

    // MARK: 토큰 적립

    /// 오늘의 provider별 누적 토큰을 받아 늘어난 만큼만 적립한다. 원장은 같은 날 안에서 절대 내려가지 않는다
    /// (일시적으로 0이나 작은 값이 읽혀도 나중에 같은 토큰을 두 번 적립하지 않도록). 반환: 이번에 받은 무료 카드 cid.
    mutating func claim<R: RandomNumberGenerator>(today: String, byProvider: [String: Int], using rng: inout R) -> [Int] {
        guard state.claimedDate != nil else {
            // 첫 실행: 설치 전 사용량은 적립하지 않는다.
            state.claimedDate = today
            state.claimedByProvider = byProvider
            return []
        }
        if state.claimedDate != today {
            state.claimedDate = today
            state.claimedByProvider = [:]
        }
        var delta = 0
        for (provider, current) in byProvider {
            let claimed = state.claimedByProvider[provider] ?? 0
            if current > claimed {
                delta += current - claimed
                state.claimedByProvider[provider] = current
            }
        }
        return credit(delta, using: &rng)
    }

    mutating func credit<R: RandomNumberGenerator>(_ tokens: Int, using rng: inout R) -> [Int] {
        guard tokens > 0 else { return [] }
        state.coinRemainder += tokens
        state.coins += state.coinRemainder / Balance.tokensPerCoin
        state.coinRemainder %= Balance.tokensPerCoin
        state.dropProgress += tokens
        var got: [Int] = []
        while state.dropProgress >= Balance.tokensPerFreeCard {
            state.dropProgress -= Balance.tokensPerFreeCard
            guard let cid = drawFree(using: &rng) else { continue }  // 전부 2장이면 게이지만 소모
            give(cid, source: "free")
            state.unseenFree += 1
            got.append(cid)
        }
        return got
    }

    // MARK: 조회

    func copies(_ cid: Int) -> Int { state.owned[cid] ?? 0 }

    var ownedDistinct: Int { state.owned.values.filter { $0 > 0 }.count }

    func progress(_ pack: Int) -> (owned: Int, total: Int) {
        let cards = db.packs[pack].cards
        return (cards.filter { copies($0.cid) > 0 }.count, cards.count)
    }

    func isUnlocked(_ pack: Int) -> Bool { pack < state.unlocked }

    // MARK: 뽑기

    /// 전체 카드 중 2장 미만인 카드를 균등 선택(잠긴 팩 카드 포함).
    func drawFree<R: RandomNumberGenerator>(using rng: inout R) -> Int? {
        db.allCIDs.filter { copies($0) < Balance.maxCopies }.randomElement(using: &rng)
    }

    mutating func give(_ cid: Int, source: String, now: Date = Date()) {
        state.owned[cid, default: 0] += 1
        state.log.insert(LogEntry(cid: cid, source: source, date: now), at: 0)
        if state.log.count > Balance.logLimit {
            state.log.removeLast(state.log.count - Balance.logLimit)
        }
        // 팩 k 가 50% 이상이면 팩 k+1 해금 (연쇄)
        while state.unlocked < db.packs.count {
            let p = progress(state.unlocked - 1)
            guard Double(p.owned) >= Double(p.total) * Balance.unlockRatio else { break }
            state.unlocked += 1
        }
    }
}
```

- [ ] **Step 3: 테스트 통과 확인**

Run: `swift test`
Expected: `Test run with 12 tests in 4 suites passed`

- [ ] **Step 4: Commit**

```bash
git add Sources/YugiTokenBar/Game.swift Tests/YugiTokenBarTests/ClaimTests.swift
git commit -m "feat: credit tokens into coins and free cards with a monotonic ledger

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: 팩 뽑기와 구매

**Files:**
- Modify: `Sources/YugiTokenBar/Game.swift`
- Test: `Tests/YugiTokenBarTests/DrawTests.swift`

**Interfaces:**
- Consumes: 작업 4의 `Game`
- Produces: `struct Pull { cid: Int; tier: Int; label: String; isNew: Bool }`, `Game.isComplete(_:) -> Bool`, `Game.canBuy(_ pack: Int, count: Int = 1) -> Bool`, `Game.draw(pack:tier:using:) -> PackCard?`, `Game.slot5Tier(using:) -> Int`, `mutating Game.buy(pack:count:using:) -> [[Pull]]` (빈 배열이면 구매 실패)

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/YugiTokenBarTests/DrawTests.swift`:
```swift
import Testing
@testable import YugiTokenBar

@Suite struct DrawTests {
    /// 팩0: 노멀 4 + 레어 1 + 울트라 1, 팩1: 노멀 4, 팩2: 노멀 2
    let db = makeDB([
        [(1, 1), (2, 1), (3, 1), (4, 1), (5, 2), (6, 4)],
        [(11, 1), (12, 1), (13, 1), (14, 1)],
        [(21, 1), (22, 1)],
    ])

    func rich(_ owned: [Int: Int] = [:], unlocked: Int = 1) -> Game {
        var state = GameState()
        state.coins = 1_000_000
        state.owned = owned
        state.unlocked = unlocked
        return Game(db: db, state: state)
    }

    @Test func neverGivesThirdCopy() {
        var game = rich()
        var rng = SeededRNG(seed: 7)
        for _ in 0..<50 { _ = game.buy(pack: 0, count: 1, using: &rng) }
        #expect(game.state.owned.values.allSatisfy { $0 <= Balance.maxCopies })
        #expect(game.isComplete(0))
    }

    @Test func emptyTierFallsDownThenUp() {
        var rng = SeededRNG(seed: 3)
        // 레어(2) 전부 2장 → 노멀로 내려감
        let down = rich([5: 2])
        #expect(down.draw(pack: 0, tier: 2, using: &rng)?.tier == 1)
        // 노멀·레어 전부 2장 → 위로 올라가 울트라
        let up = rich([1: 2, 2: 2, 3: 2, 4: 2, 5: 2])
        #expect(up.draw(pack: 0, tier: 2, using: &rng)?.cid == 6)
        // 최상위 티어 요청도 범위 밖 크래시 없이 아래로
        #expect(rich().draw(pack: 0, tier: 5, using: &rng)?.cid == 6)
    }

    @Test func packHasFourNormalsAndOneRareSlot() {
        var game = rich()
        var rng = SeededRNG(seed: 11)
        let opened = game.buy(pack: 0, count: 1, using: &rng)
        #expect(opened.count == 1)
        #expect(opened[0].count == 5)
        #expect(opened[0].prefix(4).allSatisfy { $0.tier == 1 })
        #expect(opened[0][4].tier >= 2)
        #expect(game.state.coins == 1_000_000 - Balance.packPrice)
        #expect(opened[0].filter(\.isNew).count == Set(opened[0].map(\.cid)).count)
    }

    @Test func multiBuyStopsWhenPackCompletesAndKeepsCoins() {
        // 팩2는 2종 × 2장 = 4장이면 완료 → 5팩 사도 1팩(최대 4장)만 열림
        var game = rich(unlocked: 3)
        var rng = SeededRNG(seed: 5)
        let opened = game.buy(pack: 2, count: 5, using: &rng)
        #expect(opened.count == 1)
        #expect(game.isComplete(2))
        #expect(game.state.coins == 1_000_000 - Balance.packPrice)
        #expect(game.canBuy(2) == false)
        #expect(game.buy(pack: 2, count: 1, using: &rng).isEmpty)
    }

    @Test func cannotBuyLockedOrUnaffordable() {
        var rng = SeededRNG(seed: 1)
        var locked = rich()
        #expect(locked.buy(pack: 1, count: 1, using: &rng).isEmpty)
        var poor = Game(db: db, state: GameState())
        #expect(poor.canBuy(0) == false)
        #expect(poor.buy(pack: 0, count: 1, using: &rng).isEmpty)
        var almost = rich()
        almost.state.coins = Balance.packPrice * 4
        #expect(almost.canBuy(0, count: 5) == false)
        #expect(almost.canBuy(0, count: 4))
    }

    @Test func unlockAtExactlyHalfAndChains() {
        var game = rich()
        game.give(1, source: "test")
        game.give(2, source: "test")
        #expect(game.state.unlocked == 1)  // 2/6
        game.give(3, source: "test")
        #expect(game.state.unlocked == 2)  // 3/6 = 50%
        // 잠긴 팩1 을 무료 카드로 미리 50% 채워두면 팩0 해금 순간 연쇄로 열린다
        var chain = rich([11: 1, 12: 1])
        chain.give(1, source: "free")
        chain.give(2, source: "free")
        chain.give(3, source: "free")
        #expect(chain.state.unlocked == 3)
    }

    @Test func freeCardsComeFromWholePoolAndRespectCap() {
        var game = rich()
        var rng = SeededRNG(seed: 9)
        var seenPacks = Set<Int>()
        for _ in 0..<12 {
            let cid = game.drawFree(using: &rng)!
            game.give(cid, source: "free")
            seenPacks.insert(cid / 10)
        }
        #expect(seenPacks.count > 1)  // 잠긴 팩 카드도 나온다
        #expect(game.state.owned.values.allSatisfy { $0 <= 2 })
        let full = rich(Dictionary(uniqueKeysWithValues: db.allCIDs.map { ($0, 2) }))
        #expect(full.drawFree(using: &rng) == nil)
    }

    @Test func logKeepsNewestFifty() {
        var game = rich()
        for i in 0..<60 { game.give(1 + i % 6, source: "test") }
        #expect(game.state.log.count == Balance.logLimit)
    }
}
```

Run: `swift test --filter DrawTests`
Expected: 컴파일 실패 — `value of type 'Game' has no member 'buy'`

- [ ] **Step 2: `Game.swift`에 세 부분 추가**

(a) `struct Game: Sendable {` 바로 위에:
```swift
struct Pull: Sendable, Equatable {
    let cid: Int
    let tier: Int
    let label: String
    let isNew: Bool
}
```

(b) `func isUnlocked(_ pack: Int) -> Bool { pack < state.unlocked }` 바로 아래(`// MARK: 뽑기` 위)에:
```swift
    func isComplete(_ pack: Int) -> Bool {
        db.packs[pack].cards.allSatisfy { copies($0.cid) >= Balance.maxCopies }
    }

    func canBuy(_ pack: Int, count: Int = 1) -> Bool {
        isUnlocked(pack) && !isComplete(pack) && state.coins >= Balance.packPrice * count
    }
```

(c) `drawFree` 함수와 `mutating func give` 사이에:
```swift
    /// 팩에서 tier → 아래 티어들 → 위 티어들 순으로, 2장 미만인 카드를 균등 선택.
    func draw<R: RandomNumberGenerator>(pack: Int, tier: Int, using rng: inout R) -> PackCard? {
        let order = [tier]
            + Array(stride(from: tier - 1, through: 1, by: -1))
            + Array(stride(from: tier + 1, through: 5, by: 1))
        for t in order {
            let candidates = db.packs[pack].cards.filter { $0.tier == t && copies($0.cid) < Balance.maxCopies }
            if let card = candidates.randomElement(using: &rng) { return card }
        }
        return nil
    }

    func slot5Tier<R: RandomNumberGenerator>(using rng: inout R) -> Int {
        var r = Double.random(in: 0..<1, using: &rng)
        for (tier, weight) in Balance.slot5Weights {
            if r < weight { return tier }
            r -= weight
        }
        return Balance.slot5Weights[Balance.slot5Weights.count - 1].tier
    }

    /// count 팩 구매. 도중에 팩이 완료되면 남은 팩은 사지 않는다(코인도 깎지 않음).
    mutating func buy<R: RandomNumberGenerator>(pack: Int, count: Int, using rng: inout R) -> [[Pull]] {
        guard count > 0, canBuy(pack, count: count) else { return [] }
        var opened: [[Pull]] = []
        for _ in 0..<count where !isComplete(pack) {
            state.coins -= Balance.packPrice
            let tiers = [1, 1, 1, 1, slot5Tier(using: &rng)]
            var pulls: [Pull] = []
            for tier in tiers {
                guard let card = draw(pack: pack, tier: tier, using: &rng) else { continue }
                let isNew = copies(card.cid) == 0
                give(card.cid, source: db.packs[pack].pid)
                pulls.append(Pull(cid: card.cid, tier: card.tier, label: card.label, isNew: isNew))
            }
            opened.append(pulls)
        }
        return opened
    }
```

- [ ] **Step 3: 테스트 통과 확인**

Run: `swift test`
Expected: `Test run with 20 tests in 5 suites passed`

- [ ] **Step 4: Commit**

```bash
git add Sources/YugiTokenBar/Game.swift Tests/YugiTokenBarTests/DrawTests.swift
git commit -m "feat: pack opening with tier fallback, copy cap and safe multi-buy

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: 이미지 캐시

**Files:**
- Create: `Sources/YugiTokenBar/ImageCache.swift`
- Test: `Tests/YugiTokenBarTests/ImageCacheTests.swift`

**Interfaces:**
- Produces: `@MainActor final class ImageCache { static let shared; enum Size { small, full }; init(dir:); func image(_ imageId: Int, size: Size) async -> NSImage? }`. 디스크 파일명은 `<cards_small|cards>-<imageId>.jpg`, 실패 시 `nil`(재시도는 다음 호출 때).

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/YugiTokenBarTests/ImageCacheTests.swift`:
```swift
import AppKit
import Testing
@testable import YugiTokenBar

@Suite struct ImageCacheTests {
    @MainActor @Test func servesDiskCacheWithoutNetwork() async throws {
        let dir = tempDir()
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        try rep.representation(using: .png, properties: [:])!.write(to: dir.appendingPathComponent("cards_small-123.jpg"))
        let cache = ImageCache(dir: dir)
        let image = await cache.image(123, size: .small)
        #expect(image != nil)
    }
}
```

Run: `swift test --filter ImageCacheTests`
Expected: 컴파일 실패 — `cannot find 'ImageCache' in scope`

- [ ] **Step 2: `ImageCache.swift` 작성**

```swift
import AppKit

/// YGOPRODeck 카드 이미지 디스크 + 메모리 캐시. 번들에 넣지 않고 처음 볼 때 내려받는다.
@MainActor
final class ImageCache {
    static let shared = ImageCache()

    enum Size: String, Sendable {
        case small = "cards_small"
        case full = "cards"
    }

    let dir: URL
    private var memory: [String: NSImage] = [:]
    private var inFlight: [String: Task<Data?, Never>] = [:]

    init(dir: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("YugiTokenBar")) {
        self.dir = dir
    }

    func image(_ imageId: Int, size: Size) async -> NSImage? {
        let key = "\(size.rawValue)-\(imageId)"
        if let image = memory[key] { return image }
        let task = inFlight[key] ?? Task.detached { [dir] in await Self.fetch(imageId, size: size, file: dir.appendingPathComponent("\(key).jpg")) }
        inFlight[key] = task
        let data = await task.value
        inFlight[key] = nil
        guard let data, let image = NSImage(data: data) else { return nil }
        memory[key] = image
        return image
    }

    private nonisolated static func fetch(_ imageId: Int, size: Size, file: URL) async -> Data? {
        if let data = try? Data(contentsOf: file) { return data }
        let url = URL(string: "https://images.ygoprodeck.com/images/\(size.rawValue)/\(imageId).jpg")!
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
        return data
    }
}
```

- [ ] **Step 3: 테스트 통과 확인**

Run: `swift test`
Expected: `Test run with 21 tests in 6 suites passed`

- [ ] **Step 4: Commit**

```bash
git add Sources/YugiTokenBar/ImageCache.swift Tests/YugiTokenBarTests/ImageCacheTests.swift
git commit -m "feat: disk-backed card image cache

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: 앱 셸 — 메뉴바, 요약 팝오버, 상점

**Files:**
- Create: `Sources/YugiTokenBar/AppModel.swift`, `Sources/YugiTokenBar/UI/CardImageView.swift`, `Sources/YugiTokenBar/UI/PopoverView.swift`, `Sources/YugiTokenBar/UI/ShopView.swift`
- Modify: `Sources/YugiTokenBar/App.swift` (전체 교체)

**Interfaces:**
- Consumes: `Game`, `StateStore`, `TodayUsage`, `ImageCache`, `Balance`, `Pull`
- Produces: `@MainActor final class AppModel: ObservableObject { game; opening: [[Pull]]; openingID: UUID; showShop: Bool; db; start(); refresh(); buy(pack:count:) -> Bool; markSeen() }`, `CardImageView(db:cid:size:owned:)`, `CardBack(name:glow:)`, `PackRow(index:onOpen:)`, `shortTokens(_:) -> String`. 창 id는 `"pack"`, `"dex"`(작업 8, 9에서 추가).

- [ ] **Step 1: `AppModel.swift` 작성**

```swift
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var game: Game
    /// 마지막 구매 결과 (팩 개봉 창이 보여줌)
    @Published private(set) var opening: [[Pull]] = []
    @Published private(set) var openingID = UUID()
    @Published var showShop = false

    private let store: StateStore
    private var rng = SystemRandomNumberGenerator()
    private var timer: Timer?

    init(db: CardDB, store: StateStore = .standard()) {
        self.store = store
        self.game = Game(db: db, state: store.load())
    }

    var db: CardDB { game.db }

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        Task {
            let usage = await Task.detached { TodayUsage.read() }.value
            _ = game.claim(today: usage.date, byProvider: usage.byProvider, using: &rng)
            save()
        }
    }

    @discardableResult
    func buy(pack: Int, count: Int) -> Bool {
        let opened = game.buy(pack: pack, count: count, using: &rng)
        guard !opened.isEmpty else { return false }
        opening = opened
        openingID = UUID()
        save()
        return true
    }

    func markSeen() {
        guard game.state.unseenFree > 0 else { return }
        game.state.unseenFree = 0
        save()
    }

    private func save() {
        do { try store.save(game.state) } catch { AppLog.write("state 저장 실패: \(error)") }
    }
}
```

- [ ] **Step 2: `UI/CardImageView.swift` 작성**

```swift
import SwiftUI

/// 카드 이미지. 로딩 중·실패 시 카드 뒷면 + 한국어 이름, owned=false 면 흑백 실루엣.
struct CardImageView: View {
    let db: CardDB
    let cid: Int
    var size: ImageCache.Size = .small
    var owned = true
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .grayscale(owned ? 0 : 1)
                    .brightness(owned ? 0 : -0.45)
            } else {
                CardBack(name: db.cards[cid]?.name ?? "")
            }
        }
        .aspectRatio(59.0 / 86.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .task(id: cid) {
            image = nil
            if let imageId = db.cards[cid]?.imageId {
                image = await ImageCache.shared.image(imageId, size: size)
            }
        }
    }
}

struct CardBack: View {
    var name = ""
    var glow = false

    var body: some View {
        ZStack {
            RadialGradient(colors: [Color(red: 0.35, green: 0.23, blue: 0.10), Color(red: 0.16, green: 0.09, blue: 0.03)],
                           center: .center, startRadius: 0, endRadius: 90)
            Text("遊")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Color(red: 0.85, green: 0.64, blue: 0.29))
            if !name.isEmpty {
                Text(name)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(4)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .aspectRatio(59.0 / 86.0, contentMode: .fit)
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color(red: 0.54, green: 0.35, blue: 0.17), lineWidth: 2))
        .shadow(color: glow ? .yellow : .clear, radius: glow ? 10 : 0)
    }
}
```

- [ ] **Step 3: `UI/PopoverView.swift` 작성**

```swift
import SwiftUI

struct PopoverView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if model.showShop {
                ShopView(onOpen: { show("pack") })
            } else {
                summary
            }
        }
        .padding(12)
        .frame(width: 340)
        .onAppear { model.markSeen() }
    }

    private var header: some View {
        let state = model.game.state
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("YugiTokenBar").font(.headline)
                Spacer()
                Text("🪙 \(state.coins.formatted())").font(.headline).foregroundStyle(.yellow)
            }
            Text("다음 무료 카드까지 \(shortTokens(Balance.tokensPerFreeCard - state.dropProgress))")
                .font(.caption)
            ProgressView(value: Double(state.dropProgress), total: Double(Balance.tokensPerFreeCard))
        }
    }

    private var summary: some View {
        let game = model.game
        return VStack(alignment: .leading, spacing: 8) {
            Text("최근 획득").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(Array(game.state.log.prefix(5).enumerated()), id: \.offset) { _, entry in
                    CardImageView(db: game.db, cid: entry.cid)
                        .frame(width: 56)
                        .help(game.db.cards[entry.cid]?.name ?? "")
                }
                if game.state.log.isEmpty {
                    Text("아직 카드가 없어요").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("팩 구매").font(.caption).foregroundStyle(.secondary)
            PackRow(index: game.state.unlocked - 1, onOpen: { show("pack") })
            Button("상점 전체 보기") { model.showShop = true }
                .frame(maxWidth: .infinity)
            Button("📖 도감 열기 (\(game.ownedDistinct) / \(game.db.allCIDs.count))") { show("dex") }
                .frame(maxWidth: .infinity)
            Divider()
            Button("종료") { NSApp.terminate(nil) }.font(.caption)
        }
    }

    private func show(_ id: String) {
        openWindow(id: id)
        NSApp.activate(ignoringOtherApps: true)
    }
}

func shortTokens(_ n: Int) -> String {
    n >= 1_000_000 ? String(format: "%.1fM", Double(n) / 1e6) : String(format: "%.0fK", Double(n) / 1e3)
}
```

- [ ] **Step 4: `UI/ShopView.swift` 작성**

```swift
import SwiftUI

struct ShopView: View {
    @EnvironmentObject var model: AppModel
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button("← 돌아가기") { model.showShop = false }.buttonStyle(.link)
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(model.db.packs.indices, id: \.self) { i in
                        PackRow(index: i, onOpen: onOpen)
                    }
                }
            }
            .frame(height: 420)
        }
    }
}

struct PackRow: View {
    @EnvironmentObject var model: AppModel
    let index: Int
    let onOpen: () -> Void

    var body: some View {
        let game = model.game
        let pack = game.db.packs[index]
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3)
                .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 26, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(game.isUnlocked(index) ? pack.name : "🔒 \(pack.name)").lineLimit(1)
                Text(subtitle(game)).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if game.isUnlocked(index) && !game.isComplete(index) {
                buyButton(1)
                buyButton(5)
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))
        .opacity(game.isUnlocked(index) ? 1 : 0.5)
    }

    private func subtitle(_ game: Game) -> String {
        let pack = game.db.packs[index]
        let p = game.progress(index)
        if game.isComplete(index) { return "완료 · \(p.owned)/\(p.total)" }
        if !game.isUnlocked(index) {
            return "\(game.db.packs[index - 1].name) 50% 달성 시 해금 · 보유 \(p.owned)"
        }
        return "\(pack.date.prefix(4)) · 도감 \(p.owned)/\(p.total)"
    }

    private func buyButton(_ n: Int) -> some View {
        Button("\(n)팩") {
            if model.buy(pack: index, count: n) { onOpen() }
        }
        .disabled(!model.game.canBuy(index, count: n))
        .help("\((Balance.packPrice * n).formatted())코인")
    }
}
```

- [ ] **Step 5: `App.swift` 교체 (창은 아직 없음)**

```swift
import SwiftUI

@main
struct YugiTokenBarApp: App {
    @StateObject private var model: AppModel

    init() {
        // ponytail: cards.json 은 번들 리소스이고 CardDBTests 가 검증하므로 실패 시 화면 대신 명확한 메시지로 종료
        let db: CardDB
        do { db = try CardDB.bundled() } catch { fatalError("cards.json 로드 실패: \(error)") }
        let model = AppModel(db: db)
        _model = StateObject(wrappedValue: model)
        model.start()
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView().environmentObject(model)
        } label: {
            Text(menuTitle)
        }
        .menuBarExtraStyle(.window)
    }

    private var menuTitle: String {
        let state = model.game.state
        let coins = state.coins.formatted()
        return state.unseenFree > 0 ? "🃏 \(coins) ·\(state.unseenFree)" : "🃏 \(coins)"
    }
}
```

- [ ] **Step 6: 빌드 + 테스트**

Run: `swift build && swift test`
Expected: `Build complete!`, `21 tests … passed`

- [ ] **Step 7: 격리된 세이브로 수동 확인**

```bash
rm -rf qa-state && mkdir qa-state
printf '{"coins":12000,"dropProgress":6200000,"owned":{"4007":2,"4009":1},"unlocked":2,"claimedDate":"%s","claimedByProvider":{},"unseenFree":2}' "$(date +%F)" > qa-state/state.json
YTB_STATE_DIR=$PWD/qa-state swift run YugiTokenBar
```
확인할 것:
- 메뉴바에 `🃏 12,000 ·2`가 보이고, 팝오버를 열면 `·2` 배지가 사라진다.
- 게이지에 "다음 무료 카드까지 3.8M"이 보인다(1분 안에 실제 적립이 더해지면 값이 줄어든다).
- [상점 전체 보기]에 27팩이 나온다. 1~2번 팩은 구매 버튼이 있고, 3번부터는 🔒와 "… 50% 달성 시 해금"이 보인다.
- 1팩을 사면 코인이 1,000 줄어든다. 개봉 창은 작업 8에서 생긴다.
- `qa-state/state.json`의 `claimedByProvider`가 실제 오늘 누적치로 채워진다. 첫 갱신은 원장이 비어 있어 오늘 누적치 전체가 적립되니, 코인이 크게 늘어나도 정상이다.

종료: 팝오버 [종료]

- [ ] **Step 8: Commit**

```bash
git add Sources/YugiTokenBar
git commit -m "feat: menu bar shell with summary popover and shop

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: 팩 개봉 창

**Files:**
- Create: `Sources/YugiTokenBar/UI/PackOpenView.swift`
- Modify: `Sources/YugiTokenBar/App.swift` (`.menuBarExtraStyle(.window)` 다음 줄에 Window 추가)

**Interfaces:**
- Consumes: `AppModel.opening`, `AppModel.openingID`, `CardImageView`, `CardBack`, `Pull`
- Produces: `PackOpenView`, `FlipCard(pull:db:flipped:)`

- [ ] **Step 1: `UI/PackOpenView.swift` 작성**

```swift
import SwiftUI

struct PackOpenView: View {
    @EnvironmentObject var model: AppModel
    @State private var flipped: Set<Int> = []

    var body: some View {
        let packs = model.opening
        VStack(spacing: 14) {
            if packs.count == 1 {
                HStack(spacing: 10) {
                    ForEach(Array(packs[0].enumerated()), id: \.offset) { i, pull in
                        FlipCard(pull: pull, db: model.db, flipped: flipped.contains(i))
                            .frame(width: 140)
                            .onTapGesture { withAnimation(.easeInOut(duration: 0.4)) { _ = flipped.insert(i) } }
                    }
                }
                Button("모두 뒤집기") {
                    withAnimation(.easeInOut(duration: 0.4)) { flipped = Set(packs[0].indices) }
                }
            } else if !packs.isEmpty {
                Text("\(packs.count)팩 결과").font(.headline)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(90)), count: 5), spacing: 8) {
                    ForEach(Array(packs.joined().enumerated()), id: \.offset) { _, pull in
                        FlipCard(pull: pull, db: model.db, flipped: true).frame(width: 90)
                    }
                }
            } else {
                Text("상점에서 팩을 사면 여기서 열려요").foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .onChange(of: model.openingID) { flipped = [] }
    }
}

struct FlipCard: View {
    let pull: Pull
    let db: CardDB
    let flipped: Bool

    var body: some View {
        ZStack {
            CardImageView(db: db, cid: pull.cid, size: .full)
                .overlay(alignment: .bottomLeading) { tag(pull.label, .black.opacity(0.7)) }
                .overlay(alignment: .topTrailing) {
                    if pull.isNew { tag("NEW", .pink) }
                }
                .shadow(color: pull.tier >= 2 ? .yellow : .clear, radius: 10)
                .rotation3DEffect(.degrees(flipped ? 0 : -180), axis: (x: 0, y: 1, z: 0))
                .opacity(flipped ? 1 : 0)
            CardBack(glow: pull.tier >= 2)
                .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
                .opacity(flipped ? 0 : 1)
        }
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(color, in: RoundedRectangle(cornerRadius: 3))
            .padding(4)
    }
}
```

- [ ] **Step 2: `App.swift`의 `.menuBarExtraStyle(.window)` 아래에 추가**

```swift

        Window("팩 개봉", id: "pack") {
            PackOpenView().environmentObject(model)
        }
        .windowResizability(.contentSize)
```

- [ ] **Step 3: 빌드 + 수동 확인**

Run: `swift build && YTB_STATE_DIR=$PWD/qa-state swift run YugiTokenBar`
확인할 것:
- 1팩을 사면 개봉 창이 앞으로 오고, 뒷면 5장이 보인다. 5번째 장은 뒷면부터 금색으로 빛난다.
- 클릭한 카드만 뒤집힌다. 레어도 라벨(N/R/…)이 보이고, 처음 얻은 카드에는 NEW가 붙는다.
- [모두 뒤집기]가 동작한다. 같은 창에서 1팩을 또 사면 다시 뒷면부터 시작한다.
- 5팩을 사면 25장이 결과 그리드로 나온다.
- 이미지가 로딩되기 전이나 네트워크가 꺼져 있으면 뒷면에 한국어 카드명이 보인다.

- [ ] **Step 4: Commit**

```bash
git add Sources/YugiTokenBar
git commit -m "feat: pack opening window with flip-to-reveal

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: 도감 창

**Files:**
- Create: `Sources/YugiTokenBar/UI/DexView.swift`
- Modify: `Sources/YugiTokenBar/App.swift` (팩 개봉 Window 아래에 추가)

**Interfaces:**
- Consumes: `AppModel.game`, `CardImageView(owned:)`, `Game.progress/copies/isUnlocked`
- Produces: `DexView`

- [ ] **Step 1: `UI/DexView.swift` 작성**

```swift
import SwiftUI

struct DexView: View {
    @EnvironmentObject var model: AppModel
    /// -1 = 전체
    @State private var selectedPack: Int? = 0
    @State private var selectedCard: Int?

    var body: some View {
        let game = model.game
        HStack(spacing: 0) {
            List(selection: $selectedPack) {
                Text("전체 · \(game.ownedDistinct) / \(game.db.allCIDs.count)").tag(-1)
                ForEach(game.db.packs.indices, id: \.self) { i in
                    packItem(game, i).tag(i)
                }
            }
            .frame(width: 210)

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 6)], spacing: 6) {
                    ForEach(Array(entries.enumerated()), id: \.offset) { n, entry in
                        cell(number: n + 1, cid: entry.cid, label: entry.label)
                    }
                }
                .padding(10)
            }

            Divider()
            detail.frame(width: 230)
        }
    }

    private func packItem(_ game: Game, _ i: Int) -> some View {
        let pack = game.db.packs[i]
        let p = game.progress(i)
        return VStack(alignment: .leading, spacing: 2) {
            Text(game.isUnlocked(i) ? pack.name : "🔒 \(pack.name)")
            Text("\(p.owned) / \(p.total) · \(pack.date.prefix(4))").font(.caption2).foregroundStyle(.secondary)
            ProgressView(value: Double(p.owned), total: Double(p.total)).controlSize(.mini)
        }
    }

    private var entries: [(cid: Int, label: String)] {
        let db = model.db
        if let i = selectedPack, i >= 0 { return db.packs[i].cards.map { ($0.cid, $0.label) } }
        // 전체: 팩 순서대로, 재수록은 처음 나온 팩 기준 한 번만
        var seen = Set<Int>()
        return db.packs.flatMap(\.cards).filter { seen.insert($0.cid).inserted }.map { ($0.cid, $0.label) }
    }

    private func cell(number: Int, cid: Int, label: String) -> some View {
        let n = model.game.copies(cid)
        return CardImageView(db: model.db, cid: cid, owned: n > 0)
            .overlay(alignment: .topLeading) {
                Text(String(format: "%03d", number))
                    .font(.system(size: 9)).foregroundStyle(.white)
                    .padding(2).background(.black.opacity(0.5))
            }
            .overlay(alignment: .bottomTrailing) {
                if n > 0 {
                    Text("\(label) ×\(n)")
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 3).background(.black.opacity(0.7))
                }
            }
            .help(model.db.cards[cid]?.name ?? "")
            .onTapGesture { selectedCard = cid }
    }

    @ViewBuilder private var detail: some View {
        if let cid = selectedCard, let card = model.db.cards[cid] {
            let n = model.game.copies(cid)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    CardImageView(db: model.db, cid: cid, size: .full, owned: n > 0)
                    Text(card.name).font(.headline)
                    Text([card.attr, card.level.map { "★\($0)" }, card.type].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                    if let atk = card.atk {
                        Text("공격력 \(atk) / 수비력 \(card.def ?? "-")").font(.caption)
                    }
                    Text(card.text).font(.caption).foregroundStyle(.secondary)
                    Text("\(packsText(cid)) · 보유 \(n)/\(Balance.maxCopies)")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .padding(10)
            }
        } else {
            Text("카드를 눌러 자세히 보기")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func packsText(_ cid: Int) -> String {
        model.db.packs.compactMap { pack in
            pack.cards.first { $0.cid == cid }.map { "\(pack.name) \($0.label)" }
        }.joined(separator: ", ")
    }
}
```

- [ ] **Step 2: `App.swift`의 팩 개봉 Window 아래에 추가**

```swift

        Window("도감", id: "dex") {
            DexView().environmentObject(model)
        }
        .defaultSize(width: 980, height: 640)
```

- [ ] **Step 3: 빌드 + 수동 확인**

Run: `swift build && swift test && YTB_STATE_DIR=$PWD/qa-state swift run YugiTokenBar`
확인할 것:
- [📖 도감 열기]로 창이 열리고, 왼쪽에 "전체"와 27팩, 진행도 바가 보인다.
- 가진 카드는 컬러에 `UR ×2` 같은 표시가 붙고, 없는 카드는 흑백 실루엣이다. 마우스를 올리면 이름이 나온다.
- 카드를 누르면 오른쪽에 한국어 이름, 속성, ★레벨, 종족, 공/수, 효과, "팩명 라벨", 보유 n/2가 보인다.
- "전체"를 고르면 2,270장을 스크롤할 때 버벅임이 없다(이미지는 보이는 칸만 로드).

- [ ] **Step 4: Commit**

```bash
git add Sources/YugiTokenBar
git commit -m "feat: dex window with pack list, silhouettes and Korean card detail

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: .app 번들과 설치

**Files:**
- Create: `scripts/build-app.sh`

- [ ] **Step 1: `scripts/build-app.sh` 작성**

```bash
#!/bin/bash
# YugiTokenBar.app 만들기 (개인용, ad-hoc 서명). --install 이면 /Applications 에 설치 후 실행.
set -euo pipefail
cd "$(dirname "$0")/.."
APP_NAME=YugiTokenBar
APP="build/$APP_NAME.app"

swift build -c release
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/cards.json "$APP/Contents/Resources/cards.json"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>local.yugitokenbar</string>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
codesign --force -s - "$APP"
echo "built $APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x "$APP_NAME" || true
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP" /Applications/
    open "/Applications/$APP_NAME.app"
    echo "installed /Applications/$APP_NAME.app"
fi
```

- [ ] **Step 2: 번들 빌드 + 서명 확인**

Run: `chmod +x scripts/build-app.sh && scripts/build-app.sh && codesign -v build/YugiTokenBar.app && echo ok`
Expected: `built build/YugiTokenBar.app`, `ok`

- [ ] **Step 3: 번들을 격리된 세이브로 실행 (Dock 아이콘 없이 메뉴바에만 떠야 함)**

Run: `YTB_STATE_DIR=$PWD/qa-state build/YugiTokenBar.app/Contents/MacOS/YugiTokenBar`
확인할 것: Dock 아이콘이 없고 메뉴바 항목만 있다. 상점, 개봉, 도감이 정상이다. 그다음 종료한다.

- [ ] **Step 4: 사용자 확인 후 설치**

사용자에게 `/Applications`에 설치하고 실제 세이브로 시작해도 되는지 먼저 묻는다. 승인을 받으면:
Run: `scripts/build-app.sh --install`
Expected: `installed /Applications/YugiTokenBar.app`. 첫 실행은 원장만 기록해서 코인 0으로 시작한다(설치 전 사용량 제외).

- [ ] **Step 5: Commit**

```bash
git add scripts/build-app.sh
git commit -m "chore: app bundle build and install script

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
