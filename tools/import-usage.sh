#!/bin/bash
# PokeTokenBar(MIT) 토큰 읽기 코드를 고정 커밋에서 복사하고, 이 앱에 없는 의존성을 패치한다.
# 저장소 루트에서 실행: bash tools/import-usage.sh
set -euo pipefail
SRC=${PTB_REPO:-$HOME/remote-claude-projects/code/PokeTokenBar-carryover}
REV=de617e3
DST=Sources/YugiTokenBar/Usage
mkdir -p "$DST"
for f in LocalUsageReader AppLog AppEnv BinaryLocator ClaudeAccountRoots CustomScanRoots Models ModelPricing UsageEnvironment LogRepeatSuppressor UsageCost \
         OAuthLimitsProvider KeychainAccess ProcessRunner CodexRateLimitsProvider \
         UsageProvider LocalAdditionalUsageProvider LocalAsideUsageReader LocalAntigravityUsageReader CursorUsageAPI AppStatePaths \
         LocalUsageCache; do
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
# Cursor API 캐시를 이 앱 세이브 폴더에 둔다
edit("AppStatePaths", lambda s: s.replace('"PTB_STATE_DIR"', '"YTB_STATE_DIR"').replace('appendingPathComponent("PokeTokenBar")', 'appendingPathComponent("YugiTokenBar")'))
# 파일별 사용량 캐시를 이 앱 세이브 폴더(YTB_STATE_DIR 를 따른다)에 둔다
edit("LocalUsageCache", lambda s: re.sub(r'(private static let defaultFileURL: URL = \{\n).*?(\n    \}\(\))',
     r'\1        AppStatePaths.directory().appendingPathComponent("usage-cache.json")\2', s, flags=re.S))
edit("AppLog", lambda s: s.replace("PokeTokenBar.log", "YugiTokenBar.log").replace('"poketokenbar.log"', '"yugitokenbar.log"'))
# 쓰는 중인 Claude 세션 파일은 TodayUsageReader 가 새로 붙은 줄만 읽는다: 줄 파서를 열고, 파일별 캐시가 그 파일을 건너뛰게 한다
edit("LocalUsageReader", lambda s: s.replace("    private static func parseClaudeLine(", "    static func parseClaudeLine("))
edit("LocalUsageCache", lambda s: s.replace("func claudeEntries(modifiedSince: Date) -> [LocalUsageReader.Entry] {",
     "func claudeEntries(modifiedSince: Date, skipping: Set<String> = []) -> [LocalUsageReader.Entry] {")
     .replace("all += collect(root: root, since: modifiedSince, cache: &claudeCache, annotate:",
              "all += collect(root: root, since: modifiedSince, cache: &claudeCache,\n                           include: skipping.isEmpty ? nil : { !skipping.contains($0.path) }, annotate:"))
# 매번 같은 Cursor API 상태 줄은 바뀔 때와 1시간마다만 남긴다
edit("CursorUsageAPI", lambda s: s
     .replace('AppLog.write("cursor api: session token ready', 'AppLog.writeIfChanged("cursor-api-token", "cursor api: session token ready')
     .replace('AppLog.write("cursor api: fetched ', 'AppLog.writeIfChanged("cursor-api-fetch", "cursor api: fetched ')
     .replace('AppLog.write("cursor api: fetch failed — ', 'AppLog.writeIfChanged("cursor-api-fetch", "cursor api: fetch failed — ')
     .replace('AppLog.write("cursor api: fetch failed and no cache")', 'AppLog.writeIfChanged("cursor-api-fallback", "cursor api: fetch failed and no cache")'))
PY
