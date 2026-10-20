# GitHub Releases 배포

GitHub Releases에 universal 앱 ZIP을 올린다.
앱은 Sparkle로 Release의 appcast.xml을 읽어 앱 안에서 업데이트한다.
번들 ID는 `io.github.dodant.YugiTokenBar`이며 첫 공개 뒤에는 바꾸지 않는다(기기 설정과 업데이트가 이어지지 않는다).
Apple Developer Program에 가입하지 않아 Developer ID 서명·공증 없이 ad-hoc 서명으로 게시한다.
그래서 처음 실행할 때 Gatekeeper가 막으며, 사용자는 README 설치 절대로 한 번 허용한다.
ad-hoc 서명은 빌드마다 달라 업데이트 뒤 키체인 접근(Claude 한도) 허용을 다시 물을 수 있다.
릴리스는 CI가 아니라 로컬에서 `scripts/package-release.sh --publish`로 만든다.

## 최초 설정

Sparkle 업데이트 키를 한 번 만든다.
`swift build` 뒤 `.build/artifacts/sparkle/Sparkle/bin/generate_keys`를 실행하면 개인 키는 로그인 키체인에 저장되고 공개 키가 출력된다.
공개 키를 `Resources/sparkle-public-key.txt`에 넣어 커밋한다(2026-10-20 커밋함).
공개 키가 없으면 `package-release.sh`는 시작하지 않는다.
Developer ID 없이 ad-hoc 서명한 앱끼리도 EdDSA 서명이 맞으면 Sparkle이 업데이트를 설치하고, 틀리면 받기만 하고 설치하지 않는다(2026-10-20 로컬 appcast 리허설).
개인 키를 잃으면 기존 사용자는 이후 업데이트를 받을 수 없다.
`generate_keys -x <파일>`로 내보내 안전한 곳에 백업하고, 내보낸 파일은 저장소나 대화에 두지 않는다.
앱은 `https://github.com/Dodant/YugiTokenBar/releases/latest/download/appcast.xml`(최신 Release의 첨부 파일)을 읽으므로 Release를 게시하면 업데이트가 배포된다.
`YTB_SPARKLE_FEED_URL`은 빌드할 때 피드 주소를 바꾸며, 로컬 업데이트 확인에만 쓴다.
게시에는 `gh`가 이 저장소에 쓰기 권한으로 로그인돼 있어야 한다.

## 릴리스

세 언어 CHANGELOG 맨 위 버전을 맞추고 변경 사항을 커밋·push한다.
그다음 main에서 실행한다.

```bash
scripts/package-release.sh --publish
```

스크립트는 main·깨끗한 작업 트리·HEAD = origin/main·태그와 Release가 아직 없음을 확인한다.
`swift test`·`sync-strings.py --check`·`test_make_appcast.py`를 돌린 뒤 arm64·x86_64로 빌드하고 ad-hoc 서명한다.
ZIP의 SHA-256과 키체인 개인 키로 Sparkle EdDSA 서명을 만들고, 세 언어 CHANGELOG 맨 위 항목으로 `appcast.xml`을 만든다.
`gh release create`가 HEAD에 `vX.Y.Z` 태그를 만들고 ZIP·SHA256SUMS·appcast.xml을 최신 Release로 올린다.
Release 본문은 한국어 `CHANGELOG.md`의 맨 위 버전 항목이다.
게시는 바로 공개되며, 이미 있는 태그·Release는 덮어쓰지 않는다.

## 로컬 검증과 패키징

개발용 ad-hoc 앱은 이전과 같이 `scripts/build-app.sh`로 만든다.
`--publish` 없이 `scripts/package-release.sh`를 실행하면 게시하지 않고 산출물만 `build/release/`에 만든다.
나중에 Developer ID를 받으면 `YTB_SIGN_IDENTITY='Developer ID Application: 이름 (TEAMID)'`와 `YTB_NOTARY_PROFILE`(`xcrun notarytool store-credentials`로 만든 프로필)을 주어 서명·공증·staple·Gatekeeper 검증까지 한다.
Sparkle 서명은 키체인의 개인 키를 쓴다(`YTB_SPARKLE_PRIVATE_KEY`가 있으면 그 값).
앱 저장 위치는 `~/Library/Application Support/YugiTokenBar/`이며 ZIP 교체로 지우지 않는다.

## 근거 문서

- [Apple 공증](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Sparkle EdDSA 서명](https://sparkle-project.org/documentation/)
