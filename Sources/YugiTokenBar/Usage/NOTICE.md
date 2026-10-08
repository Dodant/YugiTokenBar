# Usage/ 출처

이 폴더의 다음 파일은 [PokeTokenBar](https://github.com/chattymin/PokeTokenBar) (MIT License, Copyright (c) 2026 chattymin)
로컬 브랜치 `graduation-carryover` 커밋 `de617e3`의 `Sources/PokeTokenBar/Core/`에서 `tools/import-usage.sh`로 복사했다.

LocalUsageReader, AppLog, AppEnv, BinaryLocator, ClaudeAccountRoots, CustomScanRoots, Models, ModelPricing,
UsageEnvironment, LogRepeatSuppressor, UsageCost, OAuthLimitsProvider, KeychainAccess, ProcessRunner, CodexRateLimitsProvider,
UsageProvider, LocalAdditionalUsageProvider, LocalAsideUsageReader, LocalAntigravityUsageReader, CursorUsageAPI, AppStatePaths
(뒤의 6개는 Cursor 사용량용. Aside·Antigravity 리더는 `LocalAdditionalUsageProvider`가 참조해서 같이 복사)

## 변경점
1. `UsageCost.swift`: UI 문자열 타입 `L`에 의존하는 `text(_:compact:)`, `explanation(_:)` 제거
2. `CustomScanRoots.swift`: `curatedRoots(for:)`에서 이 앱이 쓰지 않는 사용자 지정 스캔 루트(antigravity, opencode, aside, hermes, cursor, copilot, kiro) case 제거
3. `AppLog.swift`: 로그 파일 `YugiTokenBar.log`, 큐 라벨 `yugitokenbar.log`
4. `TodayUsage.swift`(신규): 이 앱 전용 오늘 provider별 누적 토큰·비용 집계 (Claude Code·Codex·Gemini·Grok·Pi·oh-my-pi·Cursor)
5. `AppStatePaths.swift`: 환경변수 `YTB_STATE_DIR`, 기본 폴더 `YugiTokenBar` (Cursor API 캐시 위치)

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
