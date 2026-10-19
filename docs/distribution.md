# GitHub Releases 배포

GitHub Releases에 공증된 universal 앱 ZIP을 올린다.
Linux는 Flatpak 번들(베타)을 같은 Release에 올린다(아래 Linux Flatpak 베타).
앱은 Sparkle로 Release의 appcast.xml을 읽어 앱 안에서 업데이트한다.
현재 Apple Developer Program 미가입 상태이며 공개 릴리스는 보류한다.

## 최초 설정

Apple Developer Program 가입 후 Developer ID Application 인증서를 개인 키와 함께 `.p12`로 내보낸다.
Apple Development 인증서는 배포용으로 사용할 수 없다.
Sparkle 업데이트 키를 한 번 만든다.
`swift build` 뒤 `.build/artifacts/sparkle/Sparkle/bin/generate_keys`를 실행하면 개인 키는 로그인 키체인에 저장되고 공개 키가 출력된다.
공개 키를 `Resources/sparkle-public-key.txt`에 넣어 커밋한다.
공개 키가 없으면 `package-release.sh`는 시작하지 않는다.
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

태그 push는 `.github/workflows/release.yml`을 실행한다(작업 구성은 아래 릴리스 workflow).
macOS 26 runner에서 테스트·번역 검사 후 arm64·x86_64로 빌드하고 Developer ID 서명·공증·staple·Gatekeeper 검증을 한다.
최종 ZIP의 SHA-256과 Sparkle EdDSA 서명을 만들고, 세 언어 CHANGELOG 맨 위 항목으로 `appcast.xml`을 만든다.
ZIP·SHA256SUMS·appcast.xml을 Release에 올린다.
Release 본문은 한국어 `CHANGELOG.md`의 맨 위 버전 항목이다.
Mac 비밀값이 하나도 없으면 Mac 자산 없이 Linux 번들만 prerelease로 올리고, 일부만 있으면 설정 오류로 실패한다.
unsigned Mac 앱은 만들지 않는다.
이미 게시된 Release는 덮어쓰지 않는다.
초기 실패를 재시도하려면 같은 실행의 실패한 작업만 다시 실행하거나, Actions → Release → Run workflow에서 `ref`에 기존 태그를 넣고 `publish`를 켠다.

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

## Linux Flatpak 베타

앱 ID는 `io.github.dodant.YugiTokenBar`이고 manifest는 `packaging/io.github.dodant.YugiTokenBar.json`이다.
GNOME Platform·SDK 50과 `org.freedesktop.Sdk.Extension.swift6//25.08`(확인한 컴파일러 Swift 6.3.3)으로 빌드한다.
개발·CI 테스트용 Docker 이미지(`docker/linux-dev.Dockerfile`)는 Swift 6.4.1이라 Flatpak 컴파일러와 버전이 다르다.
manifest의 source는 저장소 루트(`..`)이며 `.git`·`.build*`·`build`·`qa-state`·`docs`는 넣지 않는다.
검증된 Linux 잠금 파일(`.build-linux/Package.resolved` 또는 `YTB_LINUX_LOCK`)을 builder 안에서 `Package.resolved`로 바꿔 넣고 `--force-resolved-versions`·release·`--static-swift-stdlib`로 빌드한다.
`packaging/flatpak-build.sh`가 빌드 전후 잠금 파일 SHA-256을 찍고, 바뀌면 실패한다.
설치 위치는 `/app/bin/YugiTokenBar`와 `/app/share/yugitokenbar/`(카드 JSON·picks·뒷면·파트너·lproj·세 CHANGELOG·NOTICE·`version.txt`·`licenses/<패키지>.md`)이다.
`version.txt`와 metainfo의 release 항목은 `CHANGELOG.md` 맨 위 `## x.y.z — 날짜`에서 만든다.
desktop 파일·metainfo·SVG 아이콘(직접 그린 카드 모티프)은 같은 앱 ID로 설치한다.

로컬에서 번들을 user 설치까지 해 보려면 만든 번들을 호스트의 flatpak으로 설치한다(`--arch` 기본값은 호스트 arch).

```bash
scripts/build-flatpak.sh
flatpak install --user --reinstall build/release/YugiTokenBar-<version>-<arch>.flatpak
flatpak run io.github.dodant.YugiTokenBar
```

빌드·설치 검사는 아래 스크립트가 컨테이너 안에서 한다.

```bash
scripts/build-flatpak.sh --arch aarch64     # build/release/YugiTokenBar-<version>-<arch>.flatpak, SHA256SUMS에 덧붙임
scripts/test-flatpak.sh run                 # user 설치·ldd·저장소 없는 sandbox·첫 적립과 팩 구매
scripts/test-flatpak.sh portal              # 포털 내보내기 취소·내보내기·Mac 세이브 가져오기
```

두 스크립트는 root로 flatpak을 돌리는 일회용 privileged 컨테이너에서 실행한다.
로컬은 `ytb-sdk-recovery:gnome50` 이미지(`ghcr.io/flathub-infra/flatpak-github-actions:gnome-50`에 SDK·Platform·swift6 확장을 설치한 것), CI는 같은 gnome-50 이미지를 쓴다.
`test-flatpak.sh portal`은 `xdg-desktop-portal`·`xdg-desktop-portal-gtk`·`xdotool`·`scrot`이 있는 Debian 컨테이너(flatpak과 Flathub의 GNOME Platform 50 설치)에서 실행한다.
테스트는 매번 `qa-state/flatpak/<시각>/home`을 새 HOME으로 쓰고 XDG 폴더와 `YTB_STATE_DIR`도 그 안에 두며, `XDG_RUNTIME_DIR`만 컨테이너의 `/run/user/<uid>`를 쓴다(문서 포털 경로가 sandbox와 같아야 한다).
기록은 `.build-linux/probes/flatpak/`에 남는다.

권한(finish-args)은 network·ipc·wayland·fallback-x11·dri·`home:ro`뿐이며 host shell 실행 권한은 없다.
홈은 읽기 전용이라 기본 위치의 Claude·Codex 등 로그를 읽고, 세이브 내보내기·가져오기는 파일 포털(GtkFileDialog)과 문서 포털을 거친다.
홈 밖에 둔 로그나 셸 시작 파일에만 있는 경로 변수는 sandbox에서 보이지 않는다.
세이브·백업·사용량 캐시는 `~/.var/app/io.github.dodant.YugiTokenBar/data/YugiTokenBar/`에 있고, 그 밖의 캐시와 설정은 `~/.var/app/io.github.dodant.YugiTokenBar/` 아래 `cache/`·`config/`에 있다.
Flatpak을 지워도 `flatpak uninstall --delete-data`를 쓰지 않으면 이 폴더는 남는다.

Linux Release 자산은 `YugiTokenBar-<version>-<arch>.flatpak`과 Mac ZIP까지 합친 `SHA256SUMS`이다.
x86_64는 필수이고 aarch64(`ubuntu-24.04-arm`)는 첫 베타 동안 `continue-on-error`라 실패해도 Release를 막지 않는다.
실패는 job 요약과 `linux-status-aarch64`에 `aarch64: failed`로 남기고, PR 본문에도 실패한 arch를 적는다.
aarch64 번들은 지금까지 로컬 Docker에서만 만들어 확인했고 CI arm 러너의 결과는 첫 실행 뒤에 기록한다.
Linux에는 Sparkle이 없어 자동 업데이트가 없다.
설정 > 정보 & 지원이 Setting을 열 때(실행당 성공 한 번) GitHub 최신 정식 Release를 확인해 새 버전이 있으면 알려 주고, 사용자는 새 번들을 받아 `flatpak install --user --reinstall`로 다시 설치한다.
Mac ZIP 없이 Linux만 게시하면 prerelease이고 appcast가 없으므로, Mac 앱이 읽는 최신 정식 Release를 가로채지 않는다.
사용자는 `flatpak install --user YugiTokenBar-<version>-x86_64.flatpak`으로 설치한다(GNOME Platform 50은 Flathub에서 받는다).

## 비밀값 정책과 게시 절차

Mac 비밀값 7개는 전부 있거나 전부 없어야 한다(일부만 있으면 `prepare-release`가 실패).
전부 있으면 Mac ZIP·appcast와 Linux 번들을 함께 올리고 `--latest` Release가 된다.
하나도 없으면 Linux 번들만 `--prerelease`로 올리며 Mac 자산·appcast는 없다.
Linux 빌드에는 비밀값이 필요 없다.
게시는 두 방법이다.

- 태그 push: `git tag vX.Y.Z && git push origin vX.Y.Z`(태그 버전이 `CHANGELOG.md` 맨 위와 같아야 한다).
- Actions → Release → Run workflow: `ref`에 태그를 넣고 `publish=true`.
  `publish=false`(기본)는 빌드·테스트·번들 artifact만 만들고 Release는 만들지 않는다.

prerelease는 Mac 앱이 읽는 최신 정식 Release가 아니므로 Mac 사용자의 업데이트 확인에 영향이 없다.

## 릴리스 workflow

`.github/workflows/release.yml`은 네 작업으로 나뉜다.

| 작업 | 하는 일 |
|---|---|
| `prepare-release` | 대상 commit과 CHANGELOG 버전을 정하고, Linux 잠금 파일을 dev Docker 이미지로 두 번 해석해 같은지 확인한 뒤 `linux-lock` artifact와 checksum 출력으로 넘긴다. Mac 비밀값 7개가 모두 있으면 `mac=all`, 하나도 없으면 `none`, 일부면 실패한다. |
| `build-macos` | `mac=all`일 때만 macOS 26에서 테스트·서명·공증·`package-release.sh`를 하고 ZIP·SHA256SUMS·appcast를 올린다. |
| `build-linux` | x86_64(`ubuntu-24.04`, 필수)·aarch64(`ubuntu-24.04-arm`, continue-on-error) matrix다. 받은 잠금 파일의 checksum을 확인하고 그 잠금으로 코어·모델·이미지 테스트(`scripts/test-linux-images.sh`)를 돌린 뒤 gnome-50 컨테이너에서 `build-flatpak.sh`와 `test-flatpak.sh run`을 하고 번들과 `provenance-<arch>.txt`(commit·잠금 checksum·컴파일러·runtime)를 올린다. |
| `publish` | `publish=true`이고 x86_64가 성공했을 때 artifact를 모아 `SHA256SUMS`를 다시 만들고 Release를 한 번만 만든다. Mac ZIP이 있으면 appcast와 `--latest`, 없으면 `--prerelease`다. |

비밀값은 job `if`에 쓰지 않고 `prepare-release`의 출력으로 분기한다.
재시도(실패한 작업 다시 실행)는 같은 실행의 `linux-lock` artifact를 그대로 쓴다.
새 실행은 잠금 파일을 다시 해석하므로 checksum이 달라졌으면 이전 검증을 쓰지 않고 모든 테스트·빌드·설치 검사를 다시 한다.

수동 실행 입력은 `ref`(branch·SHA·태그, 비우면 실행한 ref)와 `publish`(기본 false)다.
`publish=false`는 `ref`의 commit을 그대로 빌드하고 태그 검사를 하지 않으며 Release를 만들지 않는다.
`publish=true`나 태그 push는 그 commit에 `v<CHANGELOG 버전>` 태그가 있어야 한다.
PR head의 빌드만 확인할 때는 그 branch의 workflow 정의로 실행한다.

```bash
gh workflow run release.yml --ref feat/linux-window -f ref=<PR-head-SHA> -f publish=false
```

## 근거 문서

- [Apple 공증](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [GitHub macOS runner](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
- [Flatpak manifest](https://docs.flatpak.org/en/latest/manifests.html)
- [XDG Desktop Portal](https://flatpak.github.io/xdg-desktop-portal/)
