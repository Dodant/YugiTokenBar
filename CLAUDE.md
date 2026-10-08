# YugiTokenBar

Claude Code·Codex·Gemini·Grok·Pi·oh-my-pi·Cursor 토큰 사용량으로 한국 정발 유희왕 카드 컬렉션(정규 부스터 100팩, 8,223종. 어시스트 팩 같은 미니 팩 제외, 100팩에 없는 융합 소재는 그 융합의 팩에, 100팩 소재가 있는 조건 없는 100팩 밖 융합은 그 소재의 가장 늦은 팩에, 마스크 체인지·마스크드 히어로는 첫 수록일 직전 팩에 넣음)을 채우는 macOS 메뉴바 앱. 개인용이며 배포하지 않는다.

- 스펙: `docs/superpowers/specs/2026-10-01-yugitokenbar-design.md` (결정 사항의 기준)
- 출처: `docs/sources.md` (카드 데이터·이미지·오버프레임 21장·복사한 코드. 이미지 출처를 바꾸면 같이 고친다)
- 구현 계획: `docs/superpowers/plans/2026-10-01-yugitokenbar.md` (역사 기록. 현재 기준은 스펙)
- 실행 방식: **Subagent-driven** (superpowers:subagent-driven-development) — 사용자가 선택함

## 규칙

- 개발과 QA 실행은 항상 `YTB_STATE_DIR=$PWD/qa-state`로 한다. 실제 세이브 `~/Library/Application Support/YugiTokenBar/`는 건드리지 않는다.
- `/Applications` 설치(`scripts/build-app.sh --install`)는 사용자에게 먼저 묻는다.
- 밸런스 수치는 `Game.swift`의 `Balance`에만 둔다. 바꿀 때는 스펙 5절도 같이 고친다.
- `Sources/YugiTokenBar/Usage/`는 PokeTokenBar(MIT) 복사본이다. 직접 고치지 말고 `tools/import-usage.sh`(원본 `~/remote-claude-projects/code/PokeTokenBar-carryover`, 커밋 `de617e3`)로 다시 만든다. 바꾼 점은 `Usage/NOTICE.md`에 적는다. 캐시처럼 읽는 쪽 조정은 `Usage/` 밖 `TodayUsageReader.swift`에서 한다.
- 버전과 패치노트는 `CHANGELOG.md` 맨 위에 `## x.y.z — 날짜` 항목을 추가하는 것으로만 올린다. `build-app.sh`(Info.plist)와 앱의 업데이트 확인(main의 raw 파일)이 이 파일을 읽는다. 같은 항목을 `CHANGELOG.en.md`·`CHANGELOG.ja.md`에도 같은 `## x.y.z — 날짜` 제목으로 번역해 넣는다(앱은 언어별 파일을 보여 주고, 테스트가 세 파일의 제목을 맞춰 본다). 분류 줄은 en `**✨ New features**`·`**🎨 Improvements**`·`**⚖️ Balance**`·`**🐛 Bug fixes**`·`**⚡ Performance**`, ja `**✨ 新機能**`·`**🎨 改善**`·`**⚖️ バランス**`·`**🐛 不具合修正**`·`**⚡ パフォーマンス**`, UI 이름은 `Localizable.strings` 번역, 카드·팩 이름은 `cards_EN/JP.json` 공식 이름을 쓴다.
- 패치노트는 사용자용 문장(~했습니다)으로, 분류 줄 `**✨ 새로운 기능**`·`**🎨 개선**`·`**⚖️ 밸런스**`·`**🐛 오류 수정**`·`**⚡ 성능**` 중 해당하는 것만 쓴다. 같은 버전 안에서 바뀐 수치는 최종값만, 같은 기능은 모아서, 한 항목엔 한 주제. 내부 구조(카드 데이터 파일 형식, 해상도 등)는 빼고 커밋에만 남긴다. 큰 버전은 제목 아래에 핵심 변화 한 줄.
- `Resources/cards_KO.json`·`cards_JP.json`·`cards_EN.json`·`picks.json`(조건 소재 융합의 맞는 카드, 언어 공용)은 `python3 tools/build-cards.py`로만 다시 만든다. 옵션(`--reformat`·`--lang`)과 요청 간격·이어 받기는 스펙 3절. JP·EN은 언어당 5~9시간 걸린다.
- UI 문구는 ko/en/ja 현지화, 기준 언어는 한국어. 코드에는 한국어 문장을 그대로 쓰고(SwiftUI 리터럴은 자동, `String`으로 만드는 문구는 `String(localized:)`, 문구를 받는 헬퍼는 `LocalizedStringKey`), `python3 tools/sync-strings.py`로 en/ja `Resources/*.lproj/Localizable.strings`에 키를 덧붙여 번역한다. 커밋 전 `python3 tools/sync-strings.py --check`.
- 색은 시스템 색(`.primary`·`.secondary`·`.fill`·`accentColor`)을 먼저 쓰고, 고유한 색은 `CardImageView.swift`의 `Rarity`·`Palette`에만 라이트·다크 값을 같이 둔다(스펙 6절 외관). 화면에서 `colorScheme`으로 분기하지 않는다.
- **문서는 항상 코드와 동기화한다.** 동작·구조·명령이 바뀌면 같은 커밋에서 스펙(해당 절), `Usage/NOTICE.md`, 이 파일을 함께 고친다.
- 커밋 메시지 끝: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`

## 명령

```bash
swift test                                            # 전체 테스트
python3 tools/test_build_cards.py                     # build-cards.py 자체 검사(네트워크 없음)
python3 tools/sync-strings.py --check                 # UI 문구 키·번역 검사 (컴파일러로 키 추출, ~20초)
YTB_STATE_DIR=$PWD/qa-state swift run YugiTokenBar    # 격리된 세이브로 실행 (Claude 공식 한도·Cursor API는 안 읽음)
PTB_PARITY=1 YTB_STATE_DIR=$PWD/qa-state swift run YugiTokenBar  # 공식 한도까지 실제로 읽기
scripts/build-app.sh                                  # build/YugiTokenBar.app (ad-hoc 서명, 버전은 CHANGELOG.md)
scripts/build-app.sh && YTB_STATE_DIR=$PWD/qa-state build/YugiTokenBar.app/Contents/MacOS/YugiTokenBar -AppleLanguages '(en)'  # 언어별 QA (번역은 .app 에서만 보임, 실행 인자라 설정에 저장 안 됨)
```
