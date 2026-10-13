# Usage/ 출처

이 폴더의 다음 파일은 [PokeTokenBar](https://github.com/chattymin/PokeTokenBar) (MIT License, Copyright (c) 2026 chattymin) 로컬 브랜치 `graduation-carryover` 커밋 `de617e3`의 `Sources/PokeTokenBar/Core/`에서 `tools/import-usage.sh`로 복사했다.

LocalUsageReader, AppLog, AppEnv, BinaryLocator, ClaudeAccountRoots, CustomScanRoots, Models, ModelPricing, UsageEnvironment, LogRepeatSuppressor, UsageCost, OAuthLimitsProvider, KeychainAccess, ProcessRunner, CodexRateLimitsProvider, UsageProvider, LocalAdditionalUsageProvider, LocalAsideUsageReader, LocalAntigravityUsageReader, CursorUsageAPI, AppStatePaths, LocalUsageCache

UsageProvider~AppStatePaths 6개는 Cursor 사용량용이다.
Aside·Antigravity 리더는 `LocalAdditionalUsageProvider`가 참조해서 같이 복사했다.
LocalUsageCache는 파일별 사용량 캐시다.

## 변경점
1. `UsageCost.swift`: UI 문자열 타입 `L`에 의존하는 `text(_:compact:)`, `explanation(_:)` 제거
2. `CustomScanRoots.swift`: `curatedRoots(for:)`에서 이 앱이 쓰지 않는 사용자 지정 스캔 루트(antigravity, opencode, aside, hermes, cursor, copilot, kiro) case 제거
3. `AppLog.swift`: 로그 파일 `YugiTokenBar.log`, 큐 라벨 `yugitokenbar.log`
4. `AppStatePaths.swift`: 환경변수 `YTB_STATE_DIR`, 기본 폴더 `YugiTokenBar` (Cursor API 캐시 위치)
5. `LocalUsageCache.swift`: 디스크 캐시 `usage-cache.json`을 `AppStatePaths.directory()`(`YTB_STATE_DIR`, 없으면 `~/Library/Application Support/YugiTokenBar`)에 둔다
6. `LocalUsageReader.swift`·`LocalUsageCache.swift`: `parseClaudeLine`을 private에서 풀고, `claudeEntries(modifiedSince:skipping:)`가 주어진 경로를 건너뛴다(쓰는 중인 Claude 파일은 `TodayUsageReader`가 붙은 줄만 읽는다)
7. `CursorUsageAPI.swift`: 토큰 준비·가져오기 성공/실패·캐시 없음 로그를 `AppLog.writeIfChanged`로 남긴다(같은 줄은 바뀔 때와 1시간마다만)

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
