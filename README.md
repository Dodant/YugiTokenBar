# YugiTokenBar

코딩 에이전트 (Claude Code·Codex 등) 토큰 사용량을 보상으로 **한국 정발 유희왕 카드 컬렉션**(정규 부스터 100팩, 8,223종)을 채우는 macOS 메뉴바 앱. 개인용 토이 프로젝트다.
한국어·영어·일본어 지원(설정 › 일반 › 언어).

## 어떻게 돌아가나

- 로컬 Claude Code·Codex 세션 로그에서 오늘 쓴 토큰(input + output + cache)을 읽는다. 설치 전 사용량은 적립하지 않는다.
- 10,000 토큰 = 1코인. 1,000코인(= 1천만 토큰)으로 부스터 1팩(노멀 4 + 레어 이상 1)을 산다. 10팩을 사면 랜덤 부스터 1팩이 무료.
- 1천만 토큰마다 무료 카드 1장이 쌓이고, 직접 열면 등급 확률에 따라 전체 풀에서 나온다.
- 등급은 N / R / SR / UR / SE 5단계(UL·HR 등 UR보다 높은 레어도는 SE). 재수록 카드는 가장 높은 등급.
- 설정에서 시대 범위(DM까지~Modern까지, 기본 GX까지)를 고르면 그 시대까지의 팩·카드만 나온다.
- 같은 카드를 몇 장이든 모을 수 있다. 남는 카드는 레어도에 따라 코인으로 판다.
- 하루 5천만 토큰을 쓰면 무료 5장 + 5팩. 다 모으는 데 약 1,000억 토큰이 든다.

## 화면

- **메뉴바**: 코인, 열지 않은 무료 카드 배지
- **팝오버**: 코인, 다음 무료 카드 게이지, 쌓인 무료 카드 열기, 최근 획득 카드, 바로 구매, 오늘 사용량·비용과 Claude/Codex 공식 한도(5시간·주간)
- **상점**: DM·GX·5D's·ZEXAL·ARC-V·VRAINS·Modern 시대별로 접고 펴는 100팩 이미지 그리드(한글판 봉투), 마우스를 올리면 구매
- **팩 개봉**: 메뉴바 패널 안에서 카드를 한 장씩 뒤집어 확인(팩·무료 카드)
- **컬렉션**: 팩별 진행도, 미보유 카드는 실루엣, 등급별 보기, 한국어 카드 정보, 판매

## 요구 사항

- macOS 26 이상, Swift 6.2 (Xcode 26)
- 외부 의존성 없음

## 실행

```bash
swift test                                            # 테스트
YTB_STATE_DIR=$PWD/qa-state swift run YugiTokenBar    # 격리된 세이브로 실행
scripts/build-app.sh                                  # build/YugiTokenBar.app (ad-hoc 서명)
scripts/build-app.sh --install                        # /Applications 에 설치 후 실행
```

세이브는 `~/Library/Application Support/YugiTokenBar/`에 저장된다(`YTB_STATE_DIR`로 바꿀 수 있다). 공식 한도는 `~/.claude/.credentials.json`이나 키체인의 Claude 로그인 정보, `codex app-server`로 읽는다. `swift run`으로 개발 실행할 때는 `PTB_PARITY=1`을 붙여야 읽는다.

## 데이터

`Resources/cards_KO.json`은 `python3 tools/build-cards.py`로 만든다.

- 팩·카드 목록, 한국어 카드명·효과, 레어도: [Konami 공식 카드 DB](https://www.db.yugioh-card.com/yugiohdb/?request_locale=ko)
- 일본어·영어 카드명·효과(`cards_JP.json`·`cards_EN.json`): 같은 Konami DB 카드 상세 페이지(`request_locale=ja|en`)
- 카드 이미지: [YGOPRODeck](https://ygoprodeck.com/) (실행 중에 받아서 캐시)
- 한글판 팩 이미지: [Yugipedia](https://yugipedia.com/)

유희왕 카드의 이름·텍스트·이미지 저작권은 Konami에 있다. 이 프로젝트는 비공식 팬 프로젝트이며 Konami와 관계없다.

## 출처

`Sources/YugiTokenBar/Usage/`는 [PokeTokenBar](https://github.com/chattymin/PokeTokenBar)(MIT, © 2026 chattymin)에서 가져온 코드다. 출처와 변경점은 [`Usage/NOTICE.md`](Sources/YugiTokenBar/Usage/NOTICE.md)에 적었다.

설계 문서: [`docs/superpowers/specs/2026-10-01-yugitokenbar-design.md`](docs/superpowers/specs/2026-10-01-yugitokenbar-design.md)
