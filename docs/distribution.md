# GitHub Releases 배포

GitHub Releases에 공증된 universal 앱 ZIP을 올린다.
앱은 Sparkle로 Release의 appcast.xml을 읽어 앱 안에서 업데이트한다.
번들 ID는 `io.github.dodant.YugiTokenBar`이며 첫 공개 뒤에는 바꾸지 않는다(기기 설정과 업데이트가 이어지지 않는다).
현재 Apple Developer Program 미가입 상태이며 공개 릴리스는 보류한다.

## 최초 설정

Apple Developer Program 가입 후 Developer ID Application 인증서를 개인 키와 함께 `.p12`로 내보낸다.
Apple Development 인증서는 배포용으로 사용할 수 없다.
Sparkle 업데이트 키를 한 번 만든다.
`swift build` 뒤 `.build/artifacts/sparkle/Sparkle/bin/generate_keys`를 실행하면 개인 키는 로그인 키체인에 저장되고 공개 키가 출력된다.
공개 키를 `Resources/sparkle-public-key.txt`에 넣어 커밋한다.
공개 키가 없으면 `package-release.sh`는 시작하지 않는다.
Developer ID 없이 ad-hoc 서명한 앱끼리도 EdDSA 서명이 맞으면 Sparkle이 업데이트를 설치하고, 틀리면 받기만 하고 설치하지 않는다(2026-10-20 로컬 appcast 리허설).
`generate_keys -x sparkle-private-key.txt`로 개인 키를 내보내 아래 비밀값에 넣고 그 파일은 지운다.
앱은 `https://github.com/Dodant/YugiTokenBar/releases/latest/download/appcast.xml`(최신 Release의 첨부 파일)을 읽으므로 Release를 게시하면 업데이트가 배포된다.
`YTB_SPARKLE_FEED_URL`은 빌드할 때 피드 주소를 바꾸며, 로컬 업데이트 확인에만 쓴다.
개인 키를 잃으면 기존 사용자는 이후 업데이트를 받을 수 없으므로 키체인 백업을 유지한다.
GitHub 저장소의 Settings → Secrets and variables → Actions에 다음 비밀값을 등록한다.
비밀값은 소스나 대화에 붙여 넣지 않는다.

| Secret | 내용 |
|---|---|
| `MACOS_CERTIFICATE_P12_BASE64` | 인증서·개인 키를 내보낸 p12 파일의 Base64 |
| `MACOS_CERTIFICATE_PASSWORD` | p12 내보내기 암호 |
| `MACOS_SIGN_IDENTITY` | `Developer ID Application: 이름 (TEAMID)` |
| `APPLE_ID` | 가입한 Apple 계정 이메일 |
| `APPLE_APP_PASSWORD` | 공증용 앱 전용 암호 |
| `APPLE_TEAM_ID` | Developer Team ID |
| `SPARKLE_ED_PRIVATE_KEY` | `generate_keys -x`로 내보낸 Sparkle 개인 키 |

## 릴리스

세 언어 CHANGELOG 맨 위 버전을 맞추고 변경 사항을 커밋·push한다.
그 버전과 같은 태그를 올린다.

```bash
git tag vX.Y.Z
git push origin vX.Y.Z
```

태그 push는 `.github/workflows/release.yml`을 실행한다.
macOS 26 runner에서 테스트·번역 검사 후 arm64·x86_64로 빌드하고 Developer ID 서명·공증·staple·Gatekeeper 검증을 한다.
최종 ZIP의 SHA-256과 Sparkle EdDSA 서명을 만들고, 세 언어 CHANGELOG 맨 위 항목으로 `appcast.xml`을 만든다.
ZIP·SHA256SUMS·appcast.xml을 Release에 올린다.
Release 본문은 한국어 `CHANGELOG.md`의 맨 위 버전 항목이다.
인증서가 없으면 릴리스 게시 전에 실패하며 unsigned 릴리스를 만들지 않는다.
이미 게시된 Release는 덮어쓰지 않는다.
초기 실패를 재시도하려면 Actions → Release → Run workflow에서 기존 태그를 입력한다.

## 로컬 검증과 패키징

개발용 ad-hoc 앱은 이전과 같이 `scripts/build-app.sh`로 만든다.
공개용 ZIP은 배포 인증서와 키체인의 notarytool 프로필이 있어야 만들 수 있다.

```bash
xcrun notarytool store-credentials yugitokenbar
YTB_SIGN_IDENTITY='Developer ID Application: 이름 (TEAMID)' \
YTB_NOTARY_PROFILE=yugitokenbar scripts/package-release.sh
```

Sparkle 서명은 키체인의 개인 키를 쓴다(`YTB_SPARKLE_PRIVATE_KEY`가 있으면 그 값).

산출물은 `build/release/`에 있다.
앱 저장 위치는 `~/Library/Application Support/YugiTokenBar/`이며 ZIP 교체로 지우지 않는다.

## 근거 문서

- [Apple 공증](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [GitHub macOS runner](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
