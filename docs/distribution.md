# GitHub Releases 배포

GitHub Releases에 공증된 universal 앱 ZIP을 올린다.
앱 내부 자동 업데이트는 제공하지 않는다.
현재 Apple Developer Program 미가입 상태이며 공개 릴리스는 보류한다.

## 최초 설정

Apple Developer Program 가입 후 Developer ID Application 인증서를 개인 키와 함께 `.p12`로 내보낸다.
Apple Development 인증서는 배포용으로 사용할 수 없다.
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

## 릴리스

세 언어 CHANGELOG 맨 위 버전을 맞추고 변경 사항을 커밋·push한다.
그 버전과 같은 태그를 올린다.

```bash
git tag vX.Y.Z
git push origin vX.Y.Z
```

태그 push는 `.github/workflows/release.yml`을 실행한다.
macOS 26 runner에서 테스트·번역 검사 후 arm64·x86_64로 빌드하고 Developer ID 서명·공증·staple·Gatekeeper 검증을 한다.
최종 ZIP의 SHA-256을 계산하고 ZIP·SHA256SUMS을 Release에 올린다.
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

산출물은 `build/release/`에 있다.
앱 저장 위치는 `~/Library/Application Support/YugiTokenBar/`이며 ZIP 교체로 지우지 않는다.

## 근거 문서

- [Apple 공증](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [GitHub macOS runner](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
