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
echo "Release artifacts: build/release"
