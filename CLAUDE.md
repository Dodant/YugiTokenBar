# YugiTokenBar

토큰 사용량으로 싱크로 이전 한국 정발 유희왕 카드 도감(부스터 27팩, 2,270종)을 채우는 macOS 메뉴바 앱. 개인용이며 배포하지 않는다.

- 스펙: `docs/superpowers/specs/2026-10-01-yugitokenbar-design.md` (결정 사항의 기준)
- 구현 계획: `docs/superpowers/plans/2026-10-01-yugitokenbar.md` (작업 1~10, 코드 포함, 2026-10-01 사전 검증됨)

## 규칙

- 개발과 QA 실행은 항상 `YTB_STATE_DIR=$PWD/qa-state`로 한다. 실제 세이브 `~/Library/Application Support/YugiTokenBar/`는 건드리지 않는다.
- `/Applications` 설치(`scripts/build-app.sh --install`)는 사용자에게 먼저 묻는다.
- 밸런스 수치는 `Game.swift`의 `Balance`에만 둔다. 바꿀 때는 스펙 5절도 같이 고친다.
- `Sources/YugiTokenBar/Usage/`는 PokeTokenBar(MIT) 복사본이다. 직접 고치지 말고 `tools/import-usage.sh`(원본 `~/remote-claude-projects/code/PokeTokenBar-carryover`, 커밋 `de617e3`)로 다시 만든다. 바꾼 점은 `Usage/NOTICE.md`에 적는다.
- `Resources/cards.json`은 `python3 tools/build-cards.py`로만 다시 만든다(Konami에 1초 간격으로 요청).
- UI 문구는 한국어.
- 커밋 메시지 끝: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`

## 명령

```bash
swift test                                            # 전체 테스트
YTB_STATE_DIR=$PWD/qa-state swift run YugiTokenBar    # 격리된 세이브로 실행
scripts/build-app.sh                                  # build/YugiTokenBar.app (ad-hoc 서명)
```
