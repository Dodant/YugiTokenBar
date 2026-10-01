#!/bin/bash
# PokeTokenBar(MIT) 토큰 읽기 코드를 고정 커밋에서 복사하고, 이 앱에 없는 의존성을 패치한다.
# 저장소 루트에서 실행: bash tools/import-usage.sh
set -euo pipefail
SRC=${PTB_REPO:-$HOME/remote-claude-projects/code/PokeTokenBar-carryover}
REV=de617e3
DST=Sources/YugiTokenBar/Usage
mkdir -p "$DST"
for f in LocalUsageReader AppLog AppEnv BinaryLocator ClaudeAccountRoots CustomScanRoots Models ModelPricing UsageEnvironment LogRepeatSuppressor UsageCost \
         OAuthLimitsProvider KeychainAccess ProcessRunner CodexRateLimitsProvider; do
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
