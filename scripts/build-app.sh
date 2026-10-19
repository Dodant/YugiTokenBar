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

# 공개 배포는 universal binary, 로컬 개발은 현재 아키텍처.
if [[ "${YTB_UNIVERSAL:-0}" == "1" ]]; then
    swift build -c release --arch arm64 --arch x86_64
    BIN_DIR=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)
else
    swift build -c release
    BIN_DIR=$(swift build -c release --show-bin-path)
fi
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
# Sparkle (앱 내 업데이트). 심볼릭 링크를 살려 복사하고, 샌드박스가 아니라 XPC 서비스는 뺀다
mkdir -p "$APP/Contents/Frameworks"
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
ditto "$BIN_DIR/Sparkle.framework" "$SPARKLE"
rm -rf "$SPARKLE/XPCServices" "$SPARKLE/Versions/B/XPCServices"
cp Resources/cards_*.json Resources/picks.json "$APP/Contents/Resources/"
cp -R Resources/ko.lproj Resources/en.lproj Resources/ja.lproj "$APP/Contents/Resources/"
# 앱 아이콘: Icon Composer 파일(Resources/AppIcon.icon)을 Assets.car(Liquid Glass)·AppIcon.icns 로 컴파일
xcrun actool --compile "$APP/Contents/Resources" --app-icon AppIcon --platform macosx \
    --minimum-deployment-target 26.0 --output-partial-info-plist /dev/null Resources/AppIcon.icon >/dev/null
cp Resources/partner.png "$APP/Contents/Resources/partner.png"
cp Resources/card-back.jpg "$APP/Contents/Resources/card-back.jpg"
cp CHANGELOG.md CHANGELOG.en.md CHANGELOG.ja.md "$APP/Contents/Resources/"
cp Sources/YugiTokenBar/Usage/NOTICE.md "$APP/Contents/Resources/NOTICE.md"
cp .build/artifacts/sparkle/Sparkle/LICENSE "$APP/Contents/Resources/Sparkle-LICENSE.md"
# 공개 키는 비밀이 아니다. 파일이 없으면(키 만들기 전) 앱은 Sparkle 을 끄고 GitHub 확인만 쓴다
FEED_URL=${YTB_SPARKLE_FEED_URL:-https://github.com/Dodant/YugiTokenBar/releases/latest/download/appcast.xml}
PUBLIC_KEY_PLIST=""
if [[ -f Resources/sparkle-public-key.txt ]]; then
    PUBLIC_KEY_PLIST="<key>SUPublicEDKey</key><string>$(tr -d '[:space:]' < Resources/sparkle-public-key.txt)</string>"
fi
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>io.github.dodant.YugiTokenBar</string>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIconName</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSUIElement</key><true/>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key><array><string>en</string><string>ko</string><string>ja</string></array>
    <key>SUFeedURL</key><string>$FEED_URL</string>
    $PUBLIC_KEY_PLIST
</dict>
</plist>
PLIST
if [[ -n "${YTB_SIGN_IDENTITY:-}" ]]; then
    SIGN=(--force --options runtime --timestamp --sign "$YTB_SIGN_IDENTITY")
else
    SIGN=(--force -s -)
fi
# 안쪽부터 서명한다 (--deep 서명은 쓰지 않는다)
for target in "$SPARKLE/Versions/B/Autoupdate" "$SPARKLE/Versions/B/Updater.app" "$SPARKLE" "$APP"; do
    codesign "${SIGN[@]}" "$target"
done
codesign --verify --deep --strict "$APP"
echo "built $APP (v$VERSION, build $BUILD)"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x "$APP_NAME" || true
    while pgrep -x "$APP_NAME" >/dev/null; do sleep 0.2; done
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP" /Applications/
    open "/Applications/$APP_NAME.app"
    echo "installed /Applications/$APP_NAME.app"
fi
