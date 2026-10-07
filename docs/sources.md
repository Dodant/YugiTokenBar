# 출처

앱이 쓰는 데이터·이미지·코드의 출처를 모은 문서. 카드 이미지와 텍스트는 Konami 저작물이고, 이 앱은 개인용으로만 쓰며 배포하지 않는다(스펙). 이미지는 번들에 넣지 않고 런타임에 받아 캐시한다.

## 카드 데이터 (`Resources/cards_KO.json`, `tools/build-cards.py`)

| 무엇 | 출처 |
|---|---|
| 팩 목록·수록 카드·한국어 이름·텍스트·레어도 | Konami 공식 카드 DB 한국어판 https://www.db.yugioh-card.com/yugiohdb/ (1초 간격) |
| 이미지 ID(passcode)·영문 세트 코드 | YGOPRODeck API https://db.ygoprodeck.com/api/v7/cardinfo.php?misc=yes · https://db.ygoprodeck.com/api/v7/cardsets.php |
| 팩 표지 몬스터(`cover_card`)·한글판 봉투 이미지(`<setCode>-BoosterKR.*`) | Yugipedia API https://yugipedia.com/api.php |

## 런타임 이미지 (`ImageCache.swift`)

| 무엇 | 출처 |
|---|---|
| 카드 이미지(`cards_small`·`cards`) | YGOPRODeck https://images.ygoprodeck.com/images/ |
| 팩 봉투 | Yugipedia(한글판), 없으면 YGOPRODeck `images/sets/<setCode>.jpg` |
| 오버프레임 21장 | 아래 표 |

### 오버프레임 (`ImageCache.overframe`)

오버프레임(Over-Frame, TCG 이름 Extended art)은 일러스트가 카드 테두리 밖으로 뻗어 나오는 공식 카드 처리다. OCG에서는 LIMIT OVER COLLECTION(2026)에 처음 나왔다. 대상 카드는 Yugipedia [Extended art](https://yugipedia.com/wiki/Extended_art) 목록(약 100종)을 passcode로 `cards_KO.json`과 맞춰 뽑았고, 100팩 안에 든 21종 전부를 넣었다(2026-10-06 기준).

이미지는 SAMPLE 워터마크가 없는 것만 쓴다. Yugipedia 이미지를 먼저 쓰고(영문 RA05 UR, 일본판 LOSP PScR, CF02 공식 이미지), Yugipedia에 워터마크 판이나 이름 없는 마스터 듀얼 렌더만 있거나 이미지가 없는 9장은 일본 카드숍 상품 스캔을 쓴다(사용자 제공).

| 카드 | passcode | 수록 | 출처 | 이미지 |
|---|---|---|---|---|
| 슈팅 퀘이사 드래곤 | 35952884 | RA05 | Yugipedia | https://ms.yugipedia.com//e/e7/ShootingQuasarDragon-RA05-EN-UR-1E-EA.png |
| 패왕천룡 오드아이즈 아크레이 드래곤 | 6218704 | RA05 | Yugipedia | https://ms.yugipedia.com//a/ae/OddEyesArcrayDragon-RA05-EN-UR-1E-EA.png |
| 파이어월 드래곤 싱귤래리티 | 21637210 | RA05 | Yugipedia | https://ms.yugipedia.com//7/7c/FirewallDragonSingularity-RA05-EN-UR-1E-EA.png |
| 쿠리카라천동 | 35405755 | RA05 | Yugipedia | https://ms.yugipedia.com//c/c1/KurikaraDivincarnate-RA05-EN-UR-1E-EA.png |
| 초융합 | 48130397 | RA05 | Yugipedia | https://ms.yugipedia.com//f/f6/SuperPolymerization-RA05-EN-UR-1E-EA.png |
| 도미나스 퍼지 | 97045737 | RA05 | Yugipedia | https://ms.yugipedia.com//7/7e/DominusPurge-RA05-EN-UR-1E-EA.png |
| No.62 갤럭시아이즈 프라임 포톤 드래곤 | 31801517 | LOSP | Yugipedia | https://ms.yugipedia.com//7/77/Number62GalaxyEyesPrimePhotonDragon-LOSP-JP-PScR.png |
| 패왕룡 즈아크 | 13331639 | LOSP | Yugipedia | https://ms.yugipedia.com//f/f7/SupremeKingZARC-LOSP-JP-PScR.png |
| 카오스 앙헬－혼돈의 쌍익－ | 22850702 | LOSP | Yugipedia | https://ms.yugipedia.com//f/f2/ChaosAngel-LOSP-JP-PScR.png |
| 사로스＝에레스 쿠르누기아스 | 98127546 | LOSP | Yugipedia | https://ms.yugipedia.com//c/c1/UnderworldGoddessoftheClosedWorld-LOSP-JP-PScR.png |
| 하얀 숲의 아스테랴 | 25592142 | CF02 | Yugipedia | https://ms.yugipedia.com//5/56/AstellaroftheWhiteForest-CF02-JP-OP.png |
| 하얀 숲의 리제트 | 61980241 | CF02 | Yugipedia | https://ms.yugipedia.com//8/81/ElzetteoftheWhiteForest-CF02-JP-OP.png |
| 시작의 신 파라 | 82344137 | CORI-JP022 | 카드러시 | https://www.cardrush.jp/data/cardrush/product/CORI_OF_260424_1.jpg |
| 검은 혼돈의 마술사 블랙 카오스 | 44001993 | CORI-JP027 | 카드러시 | https://www.cardrush.jp/data/cardrush/product/CORI_OF_260424_2.jpg |
| 빛과 어둠의 전사 카오스 솔저 | 70405001 | CORI-JP028 | 카드러시 | https://www.cardrush.jp/data/cardrush/product/CORI_OF_260424_3.jpg |
| 혼돈의 삼환마 | 7894706 | CORI-JP029 | 카드러시 | https://www.cardrush.jp/data/cardrush/product/CORI_OF_260424_4.jpg |
| 도미나스 임펄스 | 40366667 | LOSP-JP020 | 카드러시 | https://www.cardrush.jp/data/cardrush/product/LOSP2_10.jpg |
| 데몬 소환 | 70781052 | VP26-JP001 | 카드러시 | https://www.cardrush.jp/data/cardrush/product/S__10100739.jpg |
| 푸른 눈의 툰 드래곤 | 53183600 | RV01-JP008 | 블루래빗 | https://www.rabbit-blue.com/data/nereid/product/RV01/008s.jpg |
| 언체인드쌍왕신 라이고우 | 29479265 | RV01-JP063 | 블루래빗 | https://www.rabbit-blue.com/data/nereid/product/RV01/063s.jpg |
| 언체인드소울킹 야마 | 24269961 | RV01-JP064 | 블루래빗 | https://www.rabbit-blue.com/data/nereid/product/RV01/064s.jpg |

새 오버프레임이 나오면 Yugipedia `Card Gallery:<영문 이름>`에서 `-EA` 파일(또는 그 상품의 스캔)을 확인해 `ImageCache.overframe`과 이 표에 한 줄씩 추가한다.

조사에 참고한 글:
- Yugipedia, Extended art: https://yugipedia.com/wiki/Extended_art
- Samurai Sword, LIMIT OVER COLLECTION 가이드: https://samuraiswordtokyo.com/ko/blogs/news/limit-over-collection-guide
- yugiohmeta, Chaos Origin 발표(오버프레임 비율): https://www.yugiohmeta.com/articles/news/2025/dec/chaos-origin-announced

## 그 밖

| 무엇 | 출처 |
|---|---|
| `Sources/YugiTokenBar/Usage/` 토큰 사용량 코드 | PokeTokenBar(MIT) https://github.com/chattymin/PokeTokenBar, 커밋 `de617e3`. 자세한 내용은 `Usage/NOTICE.md` |
| `Resources/partner.png` 날개 크리보 스프라이트 | 사용자 제공(개인용) |
| `Resources/card-back.jpg` 카드 뒷면 | Yugipedia [File:Back-KR.png](https://yugipedia.com/wiki/File:Back-KR.png)(한국판 실물 스캔 923×1351)에서 KONAMI·유희왕 로고를 지움(`tools/clean-card-back.py`) |
