# GitHub Releases 배포

GitHub Releases에 universal 앱 ZIP을 올린다.
Linux는 Flatpak 번들(베타)을 같은 Release에 올린다(아래 Linux Flatpak 베타).
앱은 Sparkle로 Release의 appcast.xml을 읽어 앱 안에서 업데이트한다.
번들 ID는 `io.github.dodant.YugiTokenBar`이며 첫 공개 뒤에는 바꾸지 않는다(기기 설정과 업데이트가 이어지지 않는다).
Apple Developer Program에 가입하지 않아 Developer ID 서명·공증 없이 ad-hoc 서명으로 게시한다.
그래서 처음 실행할 때 Gatekeeper가 막으며, 사용자는 README 설치 절차대로 한 번 허용한다.
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
`swift test`·`sync-strings.py --check`·`test_make_appcast.py`·`scripts/linux-build.sh test`를 돌린 뒤 arm64·x86_64로 빌드하고 ad-hoc 서명한다.
ZIP의 SHA-256과 키체인 개인 키로 Sparkle EdDSA 서명을 만들고, `CHANGELOG.md` 맨 위 버전의 항목을 세 언어 파일에서 찾아 `appcast.xml`을 만든다(한 파일이라도 없으면 멈춘다).
이어서 aarch64·x86_64 Linux Flatpak을 만들고 설치 검사한다(아래 Linux Flatpak 베타).
`gh release create`가 HEAD에 `vX.Y.Z` 태그를 만들고 ZIP·Flatpak 번들·SHA256SUMS·appcast.xml을 최신 Release로 올린다.
앱 ZIP 이름은 `YugiTokenBar-X.Y.Z-macOS.zip`이다(GitHub이 붙이는 소스 압축 `YugiTokenBar-X.Y.Z.zip`과 겹치지 않게, 0.6.3만 접미사 없이 게시했다).
Release 본문은 한국어 `CHANGELOG.md`의 맨 위 버전 항목이다.
게시는 바로 공개되며, 이미 있는 태그·Release는 덮어쓰지 않는다.

## 로컬 검증과 패키징

개발용 ad-hoc 앱은 이전과 같이 `scripts/build-app.sh`로 만든다.
`--publish` 없이 `scripts/package-release.sh`를 실행하면 게시하지 않고 산출물만 `build/release/`에 만든다.
나중에 Developer ID를 받으면 `YTB_SIGN_IDENTITY='Developer ID Application: 이름 (TEAMID)'`와 `YTB_NOTARY_PROFILE`(`xcrun notarytool store-credentials`로 만든 프로필)을 주어 서명·공증·staple·Gatekeeper 검증까지 한다.
Sparkle 서명은 키체인의 개인 키를 쓴다(`YTB_SPARKLE_PRIVATE_KEY`가 있으면 그 값).
앱 저장 위치는 `~/Library/Application Support/YugiTokenBar/`이며 ZIP 교체로 지우지 않는다.

## Linux Flatpak 베타

앱 ID는 `io.github.dodant.YugiTokenBar`이고 manifest는 `packaging/io.github.dodant.YugiTokenBar.json`이다.
GNOME Platform·SDK 50과 `org.freedesktop.Sdk.Extension.swift6//25.08`(확인한 컴파일러 Swift 6.3.3)으로 빌드한다.
개발·테스트용 Docker 이미지(`docker/linux-dev.Dockerfile`)는 Swift 6.4.1이라 Flatpak 컴파일러와 버전이 다르다.
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
개발 중에는 `ytb-sdk-recovery:gnome50` 이미지(`ghcr.io/flathub-infra/flatpak-github-actions:gnome-50`에 SDK·Platform·swift6 확장을 설치한 것)를, `package-release.sh`는 arch마다 그 플랫폼(`linux/arm64`·`linux/amd64`)의 gnome-50 이미지를 쓴다.
Apple Silicon에서 x86_64는 Docker 에뮬레이션이라 오래 걸린다.
`test-flatpak.sh portal`은 `xdg-desktop-portal`·`xdg-desktop-portal-gtk`·`xdotool`·`scrot`이 있는 Debian 컨테이너(flatpak과 Flathub의 GNOME Platform 50 설치)에서 실행한다.
테스트는 매번 `qa-state/flatpak/<시각>/home`을 새 HOME으로 쓰고 XDG 폴더와 `YTB_STATE_DIR`도 그 안에 두며, `XDG_RUNTIME_DIR`만 컨테이너의 `/run/user/<uid>`를 쓴다(문서 포털 경로가 sandbox와 같아야 한다).
기록은 `.build-linux/probes/flatpak/`에 남는다.

권한(finish-args)은 network·ipc·wayland·fallback-x11·dri·`home:ro`뿐이며 host shell 실행 권한은 없다.
홈은 읽기 전용이라 기본 위치의 Claude·Codex 등 로그를 읽고, 세이브 내보내기·가져오기는 파일 포털(GtkFileDialog)과 문서 포털을 거친다.
홈 밖에 둔 로그나 셸 시작 파일에만 있는 경로 변수는 sandbox에서 보이지 않는다.
세이브·백업·사용량 캐시는 `~/.var/app/io.github.dodant.YugiTokenBar/data/YugiTokenBar/`에 있고, 그 밖의 캐시와 설정은 `~/.var/app/io.github.dodant.YugiTokenBar/` 아래 `cache/`·`config/`에 있다.
Flatpak을 지워도 `flatpak uninstall --delete-data`를 쓰지 않으면 이 폴더는 남는다.

Linux Release 자산은 `YugiTokenBar-<version>-<arch>.flatpak`(x86_64·aarch64)이며 `SHA256SUMS`에 Mac ZIP과 함께 들어간다.
Linux에는 Sparkle이 없어 자동 업데이트가 없다.
설정 > 정보 & 지원이 Setting을 열 때(실행당 성공 한 번) GitHub 최신 정식 Release를 확인해 새 버전이 있으면 알려 주고, 사용자는 새 번들을 받아 `flatpak install --user --reinstall`로 다시 설치한다.
사용자는 `flatpak install --user YugiTokenBar-<version>-x86_64.flatpak`으로 설치한다(GNOME Platform 50은 Flathub에서 받는다).

## 근거 문서

- [Apple 공증](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Sparkle EdDSA 서명](https://sparkle-project.org/documentation/)
- [Flatpak manifest](https://docs.flatpak.org/en/latest/manifests.html)
- [XDG Desktop Portal](https://flatpak.github.io/xdg-desktop-portal/)
