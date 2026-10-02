#!/bin/bash
# YugiTokenBar.app 만들기 (개인용, ad-hoc 서명). --install 이면 /Applications 에 설치 후 실행.
set -euo pipefail
cd "$(dirname "$0")/.."
APP_NAME=YugiTokenBar
APP="build/$APP_NAME.app"
# 버전 원본은 CHANGELOG.md 맨 위 '## x.y.z' (앱의 AppInfo.topVersion 과 같은 규칙), 빌드 번호는 커밋 수
VERSION=$(awk '/^## [0-9]/{print $2; exit}' CHANGELOG.md)
[[ -n "$VERSION" ]] || { echo "CHANGELOG.md 에 '## x.y.z' 제목이 없음"; exit 1; }
BUILD=$(git rev-list --count HEAD)

swift build -c release
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/cards.json "$APP/Contents/Resources/cards.json"
cp CHANGELOG.md "$APP/Contents/Resources/CHANGELOG.md"
cp Sources/YugiTokenBar/Usage/NOTICE.md "$APP/Contents/Resources/NOTICE.md"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>local.yugitokenbar</string>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
codesign --force -s - "$APP"
echo "built $APP (v$VERSION, build $BUILD)"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x "$APP_NAME" || true
    while pgrep -x "$APP_NAME" >/dev/null; do sleep 0.2; done
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP" /Applications/
    open "/Applications/$APP_NAME.app"
    echo "installed /Applications/$APP_NAME.app"
fi
