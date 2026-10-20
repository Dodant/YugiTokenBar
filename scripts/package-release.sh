#!/bin/bash
# GitHub Releases용 앱 ZIP·Linux Flatpak 번들·체크섬·appcast.xml을 만든다. --publish 면 검사 뒤 Release로 게시한다.
# YTB_SIGN_IDENTITY(Developer ID)와 YTB_NOTARY_PROFILE이 있으면 서명·공증하고, 없으면 ad-hoc 서명한다.
set -euo pipefail
cd "$(dirname "$0")/.."
PUBLISH=0
[[ "${1:-}" == "--publish" ]] && PUBLISH=1
VERSION=$(awk '/^## [0-9]/{print $2; exit}' CHANGELOG.md)
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid version' >&2; exit 1; }
TAG="v$VERSION"
NOTARIZE=0
if [[ -n "${YTB_SIGN_IDENTITY:-}" ]]; then
    [[ "$YTB_SIGN_IDENTITY" == 'Developer ID Application: '* ]] || { echo 'Developer ID Application required' >&2; exit 1; }
    [[ -n "${YTB_NOTARY_PROFILE:-}" ]] || { echo 'Set YTB_NOTARY_PROFILE with YTB_SIGN_IDENTITY.' >&2; exit 1; }
    NOTARIZE=1
fi
# 공개 키 없는 앱을 내보내면 그 사용자는 Sparkle 업데이트를 받을 수 없다
[[ -s Resources/sparkle-public-key.txt ]] || { echo 'Resources/sparkle-public-key.txt missing (docs/distribution.md, Sparkle keys)' >&2; exit 1; }
if [[ $PUBLISH == 1 ]]; then
    # 게시한 커밋이 origin/main 과 같고 태그·Release가 아직 없을 때만 올린다
    [[ "$(git branch --show-current)" == main ]] || { echo 'Publish from main' >&2; exit 1; }
    [[ -z "$(git status --porcelain)" ]] || { echo 'Working tree is not clean' >&2; exit 1; }
    git fetch -q origin main --tags
    [[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || { echo 'HEAD must equal origin/main (push first)' >&2; exit 1; }
    ! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || { echo "Tag $TAG already exists" >&2; exit 1; }
    ! gh release view "$TAG" >/dev/null 2>&1 || { echo "Release $TAG already exists" >&2; exit 1; }
    swift test
    python3 tools/sync-strings.py --check
    python3 tools/test_make_appcast.py
    scripts/linux-build.sh test
fi
export YTB_UNIVERSAL=1
scripts/build-app.sh
APP=build/YugiTokenBar.app
rm -rf build/release
mkdir -p build/release
ZIP="build/release/YugiTokenBar-$VERSION-macOS.zip"
if [[ $NOTARIZE == 1 ]]; then
    ditto -c -k --keepParent "$APP" "$ZIP"
    xcrun notarytool submit "$ZIP" --keychain-profile "$YTB_NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
    xcrun stapler validate "$APP"
    spctl --assess --type execute --verbose "$APP"
    rm "$ZIP"
fi
ditto -c -k --keepParent "$APP" "$ZIP"
shasum -a 256 "$ZIP" | sed 's|build/release/||' > build/release/SHA256SUMS
# Sparkle EdDSA 서명: 비밀값이 있으면 표준 입력으로(파일로 남기지 않음), 없으면 키체인(generate_keys 저장 위치)
SIGN_UPDATE=.build/artifacts/sparkle/Sparkle/bin/sign_update
if [[ -n "${YTB_SPARKLE_PRIVATE_KEY:-}" ]]; then
    SIGNATURE=$(printf '%s' "$YTB_SPARKLE_PRIVATE_KEY" | "$SIGN_UPDATE" --ed-key-file - -p "$ZIP")
else
    SIGNATURE=$("$SIGN_UPDATE" -p "$ZIP")
fi
BUILD=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/Contents/Info.plist")
# Linux Flatpak: arch마다 그 플랫폼의 gnome-50 컨테이너에서 빌드·설치 검사 (x86_64는 Docker 에뮬레이션이라 느리다)
[[ -f .build-linux/Package.resolved ]] || scripts/linux-build.sh package resolve
for ARCH in aarch64 x86_64; do
    PLATFORM=linux/arm64; [[ $ARCH == x86_64 ]] && PLATFORM=linux/amd64
    docker run --rm --privileged --platform "$PLATFORM" -v "$PWD:/work" -w /work ghcr.io/flathub-infra/flatpak-github-actions:gnome-50 \
        bash -c "scripts/build-flatpak.sh --arch $ARCH && scripts/test-flatpak.sh run build/release/YugiTokenBar-$VERSION-$ARCH.flatpak"
done
python3 tools/make-appcast.py --version "$VERSION" --build "$BUILD" \
    --length "$(stat -f%z "$ZIP")" --signature "$SIGNATURE" > build/release/appcast.xml
echo "Release artifacts: build/release"
[[ $PUBLISH == 1 ]] || exit 0
# Release 본문은 한국어 CHANGELOG 맨 위 항목
awk '/^## [0-9]/{n++} n==1' CHANGELOG.md > build/release-notes.md
gh release create "$TAG" "$ZIP" build/release/YugiTokenBar-"$VERSION"-*.flatpak build/release/SHA256SUMS build/release/appcast.xml \
    --target "$(git rev-parse HEAD)" --title "$TAG" --notes-file build/release-notes.md --latest
git fetch -q origin --tags
echo "Published $TAG"
