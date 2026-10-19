# YugiTokenBar

Claude Code·Codex·Gemini·Grok·Pi·oh-my-pi·Cursor 토큰 사용량으로 한국 정발 유희왕 카드 컬렉션을 채우는 macOS 메뉴바 앱.
코어(게임·세이브·사용량)는 Linux에서도 빌드·테스트되며 GTK 일반 창·사이드바·저장 오류 종료 가드를 제공한다(`scripts/linux-build.sh`).
Linux의 Shop은 시대별 팩·무료 카드·무료 팩과 연출 없는 개봉 그리드를 제공한다.
Dex·Usage·Setting 본문은 3단계 후속 작업에서 연결한다.
- 컬렉션: 정규 부스터 101팩, 8,306종.
  - 어시스트 팩 같은 미니 팩 제외.
  - 101팩에 없는 융합 소재(조건 융합은 조건을 읽을 수 있을 때만)는 그 융합의 팩에 넣음.
  - 101팩 소재가 있는 조건 없는 101팩 밖 융합은 그 소재의 가장 늦은 팩에 넣음.
  - 마스크 체인지·마스크드 히어로는 첫 수록일 직전 팩에 넣음.

GitHub Releases의 ZIP으로 배포하고, 앱은 Sparkle로 Release의 appcast.xml을 읽어 업데이트한다.
첫 공개 릴리스는 Developer ID 서명·Apple 공증 설정 후 게시한다.

- 스펙: `docs/superpowers/specs/2026-10-01-yugitokenbar-design.md` (결정 사항의 기준, 로컬 전용)
- 출처: `docs/sources.md` (카드 데이터·이미지·오버프레임 25장·복사한 코드).
  이미지 출처를 바꾸면 같이 고친다.
- 배포: `docs/distribution.md` (서명·공증·릴리스 태그)
- 구현 계획: `docs/superpowers/plans/` (로컬 전용, 현재 기준은 스펙).
- superpowers 파일(`docs/superpowers/`·`.superpowers/` 등 어느 위치의 `superpowers` 폴더든)은 git에 넣지 않는다.
- 실행 방식: **Subagent-driven** (superpowers:subagent-driven-development) — 사용자가 선택함

## 규칙

- 플랫폼: SwiftUI·AppKit·Sparkle을 쓰는 파일은 첫 줄 `#if os(macOS)`, Linux 전용 진입점은 `#if os(Linux)`로 감싼다.
  Linux 전용 의존성은 `Package.swift`의 `#if os(Linux)` 블록 안에만 두고 CSQLite·swift-crypto(`exact: "3.15.1"`)·adwaita-swift(`revision: "af5598fbd6f2425841f426ad388d7a7edd6c90e6"`, `Adwaita`·`CAdw`) 외에는 더하지 않는다.
  macOS 그래프는 Sparkle 2.9.6 하나이며 `swift package show-dependencies`·`Package.resolved`를 CI에서 검사한다.
  Linux의 `Package.resolved`는 `.build-linux/`에 두고 커밋하지 않는다.
  `scripts/linux-build.sh`는 소스·리소스·패치노트를 각각 읽기 전용으로 마운트하고 Linux 잠금 파일을 쓰기 가능한 컨테이너 패키지 루트로 복사한 뒤 명령 종료 시 되돌려 복사한다.
  `String(localized:)`는 Linux에서 `Platform/Localizer.swift`가 같은 `.strings`로 처리하므로 그대로 쓴다.
  Linux UI는 `L("카드 %lld · %@", .int(count), .text(name))`처럼 단일 정적 키와 명시적 타입 인수를 쓴다.
  `sync-strings.py`는 주석·문자열을 구분해 L 키를 추출하고 위치 지정자·반복 인수·`%%`와 인수 타입을 검사한다.
  L 키의 Swift 보간·동적 식·raw/multiline 문자열은 지원하지 않는다.
  Linux는 stringsdict를 처리하지 않으므로 영어 수량은 `Free cards: N` 같은 명사형 레이블로 번역한다.
  Linux 전용 코드의 출력·로그는 영어로 쓴다(`sync-strings.py`가 한글 리터럴을 키로 본다).
  Linux에서는 공식 한도·Cursor 대시보드 API를 읽지 않고 Cursor 로컬 DB만 센다.

- 개발과 QA 실행은 항상 `YTB_STATE_DIR=$PWD/qa-state`로 한다.
  실제 세이브 `~/Library/Application Support/YugiTokenBar/`는 건드리지 않는다.
  `swift run`은 이 변수가 없어도 세이브(`state.json`)는 `qa-state`를 쓰지만, Cursor API 캐시(`PTB_PARITY=1`일 때)는 실제 폴더에 쓴다.
  `.app` 실행은 변수가 없으면 실제 세이브를 쓴다.
  `swift run`은 UI가 늘 한국어이고 카드 언어만 설정을 따른다(번역은 `.app`에서만 보인다).
  설정의 언어 메뉴를 시험했으면 끝나고 시스템 따르기로 되돌린다(번들 ID가 설치된 앱과 같아 그 설정을 같이 쓴다).
- 세이브 형식을 바꾸면(필드의 의미·타입 변경 등) `GameState.schemaVersion`을 올린다(필드 추가만이면 안 올림, 스펙 4절 저장).
- `/Applications` 설치(`scripts/build-app.sh --install`)는 사용자에게 먼저 묻는다.
- 밸런스 수치는 `Game.swift`의 `Balance`에만 둔다.
  바꿀 때는 스펙 5절도 같이 고친다.
- `Sources/YugiTokenBar/Usage/`는 PokeTokenBar(MIT) 복사본이다.
  직접 고치지 말고 `tools/import-usage.sh`(원본 `~/remote-claude-projects/code/PokeTokenBar-carryover`, 커밋 `de617e3`)로 다시 만든다.
  바꾼 점은 `Usage/NOTICE.md`에 적는다.
  파일별 캐시는 원본의 `LocalUsageCache`를 그대로 가져와 쓰고, 그 밖의 읽는 쪽 조정(provider 묶기·쓰는 중인 Claude 파일의 붙은 줄만 읽기·Cursor 증분·백오프)은 `Usage/` 밖 `TodayUsageReader.swift`에서 한다.
  `Usage/` 안은 그 조정에 필요한 접근만 `import-usage.sh` 패치로 연다.
- 버전과 패치노트는 `CHANGELOG.md` 맨 위에 `## x.y.z — 날짜` 항목을 추가하는 것으로만 올린다.
  `build-app.sh`(Info.plist)는 이 파일을 읽고, 앱의 업데이트 확인은 GitHub의 최신 정식 Release를 읽는다.
  같은 항목을 `CHANGELOG.en.md`·`CHANGELOG.ja.md`에도 같은 `## x.y.z — 날짜` 제목으로 번역해 넣는다(앱은 언어별 파일을 보여 주고, 테스트가 세 파일의 제목을 맞춰 본다).
  분류 줄과 이름은 다음을 쓴다:
  - 분류 줄 en: `**✨ New features**`·`**🎨 Improvements**`·`**⚖️ Balance**`·`**🐛 Bug fixes**`·`**⚡ Performance**`
  - 분류 줄 ja: `**✨ 新機能**`·`**🎨 改善**`·`**⚖️ バランス**`·`**🐛 不具合修正**`·`**⚡ パフォーマンス**`
  - UI 이름은 `Localizable.strings` 번역
  - 카드·팩 이름은 `cards_EN/JP.json` 공식 이름
- 패치노트는 사용자용 문장(~했습니다)으로, 분류 줄 `**✨ 새로운 기능**`·`**🎨 개선**`·`**⚖️ 밸런스**`·`**🐛 오류 수정**`·`**⚡ 성능**` 중 해당하는 것만 쓴다.
  같은 버전 안에서 바뀐 수치는 최종값만, 같은 기능은 모아서, 한 항목엔 한 주제.
  내부 구조(카드 데이터 파일 형식, 해상도 등)는 빼고 커밋에만 남긴다.
  이스터에그는 내용을 적지 않고 "어떤 카드들은 뽑으면 특별한 일이 일어나도록 했습니다." 같은 힌트 한 줄만 쓴다(내용은 스펙에 적는다).
  큰 버전은 제목 아래에 핵심 변화 한 줄.
- `Resources/cards_KO.json`·`cards_JP.json`·`cards_EN.json`·`picks.json`(만들 수 있는 융합의 소재 줄마다 맞는 카드, 언어 공용)은 `python3 tools/build-cards.py`로만 다시 만든다.
  옵션(`--reformat`·`--extras`·`--lang`)과 요청 간격·이어 받기는 스펙 3절.
  JP·EN은 언어당 5~9시간 걸린다.
- UI 문구는 ko/en/ja 현지화, 기준 언어는 한국어.
  메뉴·섹션·단순 확인·개봉 버튼의 공통 영어 표기(Shop·Dex·Setting·Cards·Decks·Partner·OK·Open), 사용량(메뉴 사용량 칸·사용량 화면) 문구는 세 언어 `Localizable.strings`에서 같은 영어 값으로 지정한다.
  설정 > 정보 & 지원의 GitHub Repo 줄·크레딧·출처 줄(Inspired by PokeTokenBar·License·Card data & images·Unofficial fan project와 힌트), 설정 맨 아래 Made with Love and Claude, 라이선스 창 제목처럼 세 언어가 같은 영어 문구는 코드에 영어 키를 그대로 쓴다(번역 파일에 항목을 두지 않는다).
  한국어 파일에는 이 영어 표기만 넣고, 다른 문구는 코드의 한국어 키를 그대로 쓴다.
  코드에는 한국어 문장을 그대로 쓰고, `python3 tools/sync-strings.py`로 en/ja `Resources/*.lproj/Localizable.strings`에 키를 덧붙여 번역한다.
  - SwiftUI 리터럴은 자동.
  - `String`으로 만드는 문구는 `String(localized:)`.
  - 문구를 받는 헬퍼는 `LocalizedStringKey`.
  - 영어 단수·복수가 갈리는 문구는 `en.lproj/Localizable.stringsdict`에 복수 규칙을 더한다(키는 strings에도 둔다).
  - 번역 어조·위치 지정자·유희왕 용어집은 스펙 6절 공통 UI 표기.

  커밋 전 `python3 tools/sync-strings.py --check`.
- 설정은 저장 위치를 나눈다.
  기기 설정(언어·업무 모드)은 UserDefaults, 게임 설정은 세이브(`GameState`)에 둔다.
  새 설정을 더할 때 어느 쪽인지 스펙 6절 설정 항목에 적는다.
- 이미지 URL·캐시 키는 `ImageSource.swift`, 디스크·HTTP 바이트 전송은 `ImageTransport.swift`에서 공유하며, macOS 디코딩·메모리 캐시·waiter 취소는 `ImageCache.swift`에 둔다.
- Linux 이미지는 `LinuxImageLoader`가 source key별 전송을 공유하며 마지막 widget 구독이 사라지면 취소한다.
  worker는 Data만 inbox에 넣고 기존 100ms GTK drain이 tick당 결과 2개(크기별 최대 4회 디코딩)를 처리한다.
  `LinuxTextureCache`는 비율을 유지해 grid 300px·detail 614px로 축소하며 96개/추정 RGBA 32MiB를 LRU로 유지한다.
  cache와 GTK picture는 각자 ref를 소유하므로 화면의 widget ref까지 포함한 전체 프로세스 메모리 상한은 아니다.
  `LinuxPicture`는 GObject weak notification에서 구독을 해제하고 lifecycle stop/resume은 살아 있는 구독자를 새 flight로 재개한다.
  `YTB_SMOKE_NO_IMAGES=1`은 디스크 캐시·네트워크 전송을 모두 생략하고 bundled card-back만 표시한다.
  호출자는 오버프레임 URL 존재 여부가 아니라 `game.showsOverframe(cid)`를 `ImageSource.card`에 전달한다.
  개봉 화면은 획득 당시 해금 여부인 `Pull.overframe`을 사용해 뒤에 해금된 그림을 앞선 카드에 소급하지 않는다.
- Linux Shop의 `LinuxModel.canBuy(pack:)`를 버튼 sensitive와 구매 명령이 공유한다.
  잔액 부족·개봉 중·범위 밖은 거절하고 `cleared` 팩은 `wanted && !isFusionOnly`인 실제 뽑을 수 있는 필요 카드가 있어야 구매할 수 있다.
  미보유 융합만 남으면 FUSION ONLY를 표시하고 막되 더 필요한 오버프레임·융합 소재가 있으면 구매할 수 있다.
  개봉 중 구매·무료 카드·무료 팩 명령을 거절하고 닫기 또는 사이드바 Shop 재선택으로 목록에 돌아간다.
  무료 카드는 `Balance.freeOpenBatch`(현재 6장)만큼 열며 무료 팩은 기존 무작위 팩 규칙을 쓴다.
- Linux 상태 변경·저장은 `@MainActor LinuxModel`에서 직렬화하고 백그라운드 사용량 결과는 Sendable 값으로 `LinuxInbox`에만 넣는다.
  GTK 루프가 `drainEvents()`를 호출하며 request ID·state generation·lifecycle epoch로 오래된 결과를 버린다.
  읽는 동안 들어온 갱신 요청은 겹치지 않는 후속 읽기 한 번으로 모으고 결과를 현재 게임에 적립한다.
  주기 갱신은 조용히 수행하며 실제 스냅샷 내용이 바뀔 때만 발행하고 게임 상태가 그대로면 다시 저장하지 않는다.
  저장 실패는 메모리에 보존하고 다음 동일 읽기나 명시적 재시도에서 다시 저장한다.
  추가 스캔 폴더 변경은 `resetUsageReader()`로 기록 캐시를 지우고 reader와 generation을 새로 만든다.
- Linux GTK 진입점은 `Linux/LinuxApp.swift`이며 `LinuxShellView`의 값 스냅샷을 model callback으로 갱신한다.
  Meta의 optional `@State`는 초기 nil cast를 피하도록 `rawValue`를 명시적으로 초기화한다.
  시작 때 DB·세이브 잠금·상위 schema를 검사하고 복구 알림을 보여 준다.
  GLib 100ms inbox·60초 갱신 source는 weak model과 등록 시 불변 lifecycle epoch를 캡처하며 활성화가 반복돼도 중복 등록하지 않는다.
  창 닫기와 Ctrl+Q는 같은 저장 재시도·취소·변경 폐기 종료 가드를 거치고 종료 전에 모델을 멈추고 로그를 flush한다.
  저장 재시도 실패 알림은 GTK 응답의 자동 닫기 이후 Idle에서 다시 표시한다.
  사이드바의 provider 합계는 sampled day를 함께 표시해 자정 뒤 이전 사용량을 오늘 값으로 바꾸지 않는다.
- 색은 시스템 색(`.primary`·`.secondary`·`.fill`·`accentColor`)을 먼저 쓰고, 고유한 색은 `CardImageView.swift`의 `Rarity`·`Palette`에만 라이트·다크 값을 같이 둔다(스펙 6절 외관).
  화면에서 `colorScheme`으로 분기하지 않는다.
- **문서는 항상 코드와 동기화한다.**
  동작·구조·명령이 바뀌면 같은 커밋에서 스펙(해당 절), `Usage/NOTICE.md`, 이 파일을 함께 고친다.
- 문서(.md)는 한 줄에 한 문장으로 쓴다.
  문장이 끝나면 줄을 바꾸고, 목록 항목이면 내용 칸만큼 들여 쓴다(렌더링은 같다).
  표·코드 블록은 예외.
  `CHANGELOG*.md`는 앱이 줄 단위로 그리므로 항목 하나를 한 줄로 둔다.
- 커밋 메시지 끝: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`

## 명령

```bash
swift test                                            # 전체 테스트
scripts/linux-build.sh test                           # Docker(Swift 6.4.1·GTK 4·libadwaita) Linux 테스트, 이미지 캐시 갱신·산출물·핀 .build-linux/
scripts/linux-build.sh build                          # GTK 실행 파일 빌드 (실행은 GTK 디스플레이·DBus 세션 필요)
scripts/test-linux-images.sh                         # Xvfb 실제 GTK 이미지·소유권·취소 검사(선택: YTB_GTK_IMAGE_ONLINE=1)
scripts/test-linux-ui.sh                             # Xvfb 실제 Shop·Dex 버튼·개봉·상세·판매·저장 검사
python3 tools/test_build_cards.py                     # build-cards.py 자체 검사(네트워크 없음)
python3 tools/test_make_appcast.py                    # make-appcast.py 자체 검사(네트워크 없음)
python3 tools/test_sync_strings.py                    # Linux L 키 scanner·형식 인수 검사(네트워크 없음)
python3 tools/sync-strings.py --check                 # UI 문구 키·번역·en 문자 체계·en 복수형 검사 (컴파일러로 키 추출, ~20초)
YTB_STATE_DIR=$PWD/qa-state swift run YugiTokenBar    # 격리된 세이브로 실행 (Claude 공식 한도·Cursor API는 안 읽음)
PTB_PARITY=1 YTB_STATE_DIR=$PWD/qa-state swift run YugiTokenBar  # 공식 한도·Cursor API까지 실제로 읽기
scripts/build-app.sh                                  # build/YugiTokenBar.app (ad-hoc 서명, 버전은 CHANGELOG.md)
YTB_SIGN_IDENTITY=… YTB_NOTARY_PROFILE=… scripts/package-release.sh  # 공개용 서명·공증 ZIP (docs/distribution.md)
scripts/build-app.sh && YTB_STATE_DIR=$PWD/qa-state build/YugiTokenBar.app/Contents/MacOS/YugiTokenBar -AppleLanguages '(en)'  # 언어별 QA (번역은 .app 에서만 보임, 실행 인자라 설정에 저장 안 됨)
```
