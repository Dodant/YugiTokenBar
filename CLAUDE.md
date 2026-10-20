# YugiTokenBar

Claude Code·Codex·Gemini·Grok·Pi·oh-my-pi·Cursor 토큰 사용량으로 한국 정발 유희왕 카드 컬렉션을 채우는 macOS 메뉴바 앱.
코어(게임·세이브·사용량)는 Linux에서도 빌드·테스트된다(`scripts/linux-build.sh`, Linux 창은 설계 문서 2026-10-16의 3단계).
- 컬렉션: 정규 부스터 101팩, 8,306종.
  - 어시스트 팩 같은 미니 팩 제외.
  - 101팩에 없는 융합 소재(조건 융합은 조건을 읽을 수 있을 때만)는 그 융합의 팩에 넣음.
  - 101팩 소재가 있는 조건 없는 101팩 밖 융합은 그 소재의 가장 늦은 팩에 넣음.
  - 마스크 체인지·마스크드 히어로는 첫 수록일 직전 팩에 넣음.

GitHub Releases의 ZIP으로 배포하고, 앱은 Sparkle로 Release의 appcast.xml을 읽어 업데이트한다.
Developer ID·공증 없이 ad-hoc 서명으로, CI가 아니라 로컬에서 `scripts/package-release.sh --publish`로 게시한다(게시는 사용자 확인 후).

- 스펙: `docs/superpowers/specs/2026-10-01-yugitokenbar-design.md` (결정 사항의 기준, 로컬 전용)
- 출처: `docs/sources.md` (카드 데이터·이미지·오버프레임 25장·복사한 코드).
  이미지 출처를 바꾸면 같이 고친다.
- 배포: `docs/distribution.md` (Sparkle 키·로컬 릴리스·Gatekeeper)
- 구현 계획: `docs/superpowers/plans/` (로컬 전용, 현재 기준은 스펙).
- superpowers 파일(`docs/superpowers/`·`.superpowers/` 등 어느 위치의 `superpowers` 폴더든)은 git에 넣지 않는다.
- 실행 방식: **Subagent-driven** (superpowers:subagent-driven-development) — 사용자가 선택함

## 규칙

- 플랫폼: SwiftUI·AppKit·Sparkle을 쓰는 파일은 첫 줄 `#if os(macOS)`, Linux 전용 진입점은 `#if os(Linux)`로 감싼다.
  Linux 전용 의존성은 `Package.swift`의 `#if os(Linux)` 블록 안에만 두고 CSQLite·swift-crypto(현재 `exact: "3.15.1"`, 3단계에서 adwaita-swift) 외에는 더하지 않는다.
  macOS 그래프는 Sparkle 2.9.6 하나이며 `swift package show-dependencies`·`Package.resolved`를 CI에서 검사한다.
  Linux의 `Package.resolved`는 `.build-linux/`에 두고 커밋하지 않는다.
  `scripts/linux-build.sh`는 소스·리소스·패치노트를 각각 읽기 전용으로 마운트하고 Linux 잠금 파일을 쓰기 가능한 컨테이너 패키지 루트로 복사한 뒤 명령 종료 시 되돌려 복사한다.
  `String(localized:)`는 Linux에서 `Platform/Localizer.swift`가 같은 `.strings`로 처리하므로 그대로 쓴다.
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
  직접 고치지 말고 `PTB_REPO=<PokeTokenBar 체크아웃> tools/import-usage.sh`(커밋 `de617e3`)로 다시 만든다.
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
- 색은 시스템 색(`.primary`·`.secondary`·`.fill`·`accentColor`)을 먼저 쓰고, 고유한 색은 `CardImageView.swift`의 `Rarity`·`Palette`에만 라이트·다크 값을 같이 둔다(스펙 6절 외관).
  화면에서 `colorScheme`으로 분기하지 않는다.
- **문서는 항상 코드와 동기화한다.**
  동작·구조·명령이 바뀌면 같은 커밋에서 스펙(해당 절), `Usage/NOTICE.md`, 이 파일을 함께 고친다.
- 문서(.md)는 한 줄에 한 문장으로 쓴다.
  문장이 끝나면 줄을 바꾸고, 목록 항목이면 내용 칸만큼 들여 쓴다(렌더링은 같다).
  표·코드 블록은 예외.
  `CHANGELOG*.md`도 항목이 여러 문장이면 둘째 문장부터 두 칸 들여 다음 줄에 쓴다(앱은 그 줄을 같은 항목으로 그린다).
- 커밋 메시지 끝: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`

## 명령

```bash
swift test                                            # 전체 테스트
scripts/linux-build.sh test                           # Docker(swift:6.4.1) Linux 코어 테스트, 산출물·핀 .build-linux/
scripts/linux-build.sh run YugiTokenBar               # Linux CLI, 격리 qa-state 사용
python3 tools/test_build_cards.py                     # build-cards.py 자체 검사(네트워크 없음)
python3 tools/test_make_appcast.py                    # make-appcast.py 자체 검사(네트워크 없음)
python3 tools/sync-strings.py --check                 # UI 문구 키·번역·en 문자 체계·en 복수형 검사 (컴파일러로 키 추출, ~20초)
YTB_STATE_DIR=$PWD/qa-state swift run YugiTokenBar    # 격리된 세이브로 실행 (Claude 공식 한도·Cursor API는 안 읽음)
PTB_PARITY=1 YTB_STATE_DIR=$PWD/qa-state swift run YugiTokenBar  # 공식 한도·Cursor API까지 실제로 읽기
scripts/build-app.sh                                  # build/YugiTokenBar.app (ad-hoc 서명, 버전은 CHANGELOG.md)
scripts/package-release.sh                            # 릴리스 ZIP·appcast.xml만 build/release/에 (ad-hoc, Sparkle 서명은 키체인 키)
scripts/package-release.sh --publish                  # 검사 후 vX.Y.Z 태그와 GitHub Release 게시 (main = origin/main 일 때만, 사용자 확인 후)
scripts/build-app.sh && YTB_STATE_DIR=$PWD/qa-state build/YugiTokenBar.app/Contents/MacOS/YugiTokenBar -AppleLanguages '(en)'  # 언어별 QA (번역은 .app 에서만 보임, 실행 인자라 설정에 저장 안 됨)
```
