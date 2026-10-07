# YugiTokenBar

Claude Code·Codex·Gemini·Grok·Pi·Cursor 토큰 사용량으로 한국 정발 유희왕 카드 컬렉션(정규 부스터 100팩, 8,172종. 어시스트 팩 같은 미니 팩 제외)을 채우는 macOS 메뉴바 앱. 개인용이며 배포하지 않는다.

- 스펙: `docs/superpowers/specs/2026-10-01-yugitokenbar-design.md` (결정 사항의 기준)
- 출처: `docs/sources.md` (카드 데이터·이미지·오버프레임 21장·복사한 코드. 이미지 출처를 바꾸면 같이 고친다)
- 구현 계획: `docs/superpowers/plans/2026-10-01-yugitokenbar.md` (작업 1~10, 코드 포함, 2026-10-01 사전 검증됨)
- 실행 방식: **Subagent-driven** (superpowers:subagent-driven-development) — 사용자가 선택함

## 규칙

- 개발과 QA 실행은 항상 `YTB_STATE_DIR=$PWD/qa-state`로 한다. 실제 세이브 `~/Library/Application Support/YugiTokenBar/`는 건드리지 않는다.
- `/Applications` 설치(`scripts/build-app.sh --install`)는 사용자에게 먼저 묻는다.
- 밸런스 수치는 `Game.swift`의 `Balance`에만 둔다. 바꿀 때는 스펙 5절도 같이 고친다.
- `Sources/YugiTokenBar/Usage/`는 PokeTokenBar(MIT) 복사본이다. 직접 고치지 말고 `tools/import-usage.sh`(원본 `~/remote-claude-projects/code/PokeTokenBar-carryover`, 커밋 `de617e3`)로 다시 만든다. 바꾼 점은 `Usage/NOTICE.md`에 적는다. 캐시처럼 읽는 쪽 조정은 `Usage/` 밖 `TodayUsageReader.swift`에서 한다.
- 버전과 패치노트는 `CHANGELOG.md` 맨 위에 `## x.y.z — 날짜` 항목을 추가하는 것으로만 올린다. `build-app.sh`(Info.plist)와 앱의 업데이트 확인(main의 raw 파일)이 이 파일을 읽는다.
- 패치노트는 사용자용 문장(~했습니다)으로, 분류 줄 `**✨ 새로운 기능**`·`**🎨 개선**`·`**⚖️ 밸런스**`·`**🐛 오류 수정**`·`**⚡ 성능**` 중 해당하는 것만 쓴다. 같은 버전 안에서 바뀐 수치는 최종값만, 같은 기능은 모아서, 한 항목엔 한 주제. 내부 구조(cards.json 형식, 해상도 등)는 빼고 커밋에만 남긴다. 큰 버전은 제목 아래에 핵심 변화 한 줄.
- `Resources/cards.json`은 `python3 tools/build-cards.py`로만 다시 만든다(Konami에 1초 간격으로 요청). 형식만 다시 쓸 때는 `--reformat`(네트워크 없음).
- UI 문구는 한국어.
- 색은 시스템 색(`.primary`·`.secondary`·`.fill`·`accentColor`)을 먼저 쓰고, 고유한 색은 `CardImageView.swift`의 `Rarity`·`Palette`에만 라이트·다크 값을 같이 둔다(스펙 6절 외관). 화면에서 `colorScheme`으로 분기하지 않는다.
- **문서는 항상 코드와 동기화한다.** 동작·구조·명령이 바뀌면 같은 커밋에서 스펙(해당 절), `Usage/NOTICE.md`, 이 파일을 함께 고친다.
- 커밋 메시지 끝: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`

## 명령

```bash
swift test                                            # 전체 테스트
YTB_STATE_DIR=$PWD/qa-state swift run YugiTokenBar    # 격리된 세이브로 실행 (공식 한도는 안 읽음)
PTB_PARITY=1 YTB_STATE_DIR=$PWD/qa-state swift run YugiTokenBar  # 공식 한도까지 실제로 읽기
scripts/build-app.sh                                  # build/YugiTokenBar.app (ad-hoc 서명, 버전은 CHANGELOG.md)
```
