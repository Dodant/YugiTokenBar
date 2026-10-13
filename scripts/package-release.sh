#!/bin/bash
# GitHub Releases용 공증된 앱 ZIP과 체크섬을 만든다.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(awk '/^## [0-9]/{print $2; exit}' CHANGELOG.md)
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid version' >&2; exit 1; }
[[ -n "${YTB_SIGN_IDENTITY:-}" && -n "${YTB_NOTARY_PROFILE:-}" ]] || {
    echo 'Set YTB_SIGN_IDENTITY (Developer ID Application) and YTB_NOTARY_PROFILE.' >&2; exit 1;
}
[[ "$YTB_SIGN_IDENTITY" == 'Developer ID Application: '* ]] || { echo 'Developer ID Application required' >&2; exit 1; }
# 공개 키 없는 앱을 내보내면 그 사용자는 Sparkle 업데이트를 받을 수 없다
[[ -s Resources/sparkle-public-key.txt ]] || { echo 'Resources/sparkle-public-key.txt missing (docs/distribution.md, Sparkle keys)' >&2; exit 1; }
export YTB_UNIVERSAL=1
scripts/build-app.sh
APP=build/YugiTokenBar.app
mkdir -p build/release
ZIP="build/release/YugiTokenBar-$VERSION.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$YTB_NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose "$APP"
rm "$ZIP"
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
python3 tools/make-appcast.py --version "$VERSION" --build "$BUILD" \
    --length "$(stat -f%z "$ZIP")" --signature "$SIGNATURE" > build/release/appcast.xml
echo "Release artifacts: build/release"
