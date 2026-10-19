#!/bin/sh
# Runs inside flatpak-builder (packaging/io.github.dodant.YugiTokenBar.json): builds against the verified Linux lock
# and installs the binary, resources, version, notices and desktop integration under /app.
set -eu
id=io.github.dodant.YugiTokenBar
share=/app/share/yugitokenbar
cp linux.resolved Package.resolved
before=$(sha256sum Package.resolved | cut -d' ' -f1)
echo "LOCK_SHA256 before=$before"
swift --version
swift build -c release --static-swift-stdlib --force-resolved-versions
after=$(sha256sum Package.resolved | cut -d' ' -f1)
echo "LOCK_SHA256 after=$after"
[ "$before" = "$after" ] || { echo "Package.resolved changed during the build" >&2; exit 1; }

bin=$(swift build -c release --static-swift-stdlib --show-bin-path)
install -Dm755 "$bin/YugiTokenBar" /app/bin/YugiTokenBar
mkdir -p "$share/licenses"
cp Resources/cards_KO.json Resources/cards_EN.json Resources/cards_JP.json Resources/picks.json \
   Resources/card-back.jpg Resources/partner.png CHANGELOG.md CHANGELOG.en.md CHANGELOG.ja.md "$share/"
cp -R Resources/ko.lproj Resources/en.lproj Resources/ja.lproj "$share/"
cp Sources/YugiTokenBar/Usage/NOTICE.md "$share/NOTICE.md"
version=$(awk '/^## [0-9]/{print $2; exit}' CHANGELOG.md)
date=$(awk '/^## [0-9]/{print $4; exit}' CHANGELOG.md)
printf '%s\n' "$version" > "$share/version.txt"
for dir in .build/checkouts/*; do
    license=$(ls "$dir" | grep '^LICENSE' | sort | head -1 || true)
    [ -n "$license" ] && cp "$dir/$license" "$share/licenses/$(basename "$dir").md"
done
ls "$share/licenses"

install -Dm644 packaging/$id.desktop /app/share/applications/$id.desktop
install -Dm644 packaging/$id.svg /app/share/icons/hicolor/scalable/apps/$id.svg
# The release entry follows the CHANGELOG top heading (## x.y.z — YYYY-MM-DD), like version.txt.
sed "s|<release version=\"[^\"]*\" date=\"[^\"]*\"/>|<release version=\"$version\" date=\"$date\"/>|" \
    packaging/$id.metainfo.xml > metainfo.xml
install -Dm644 metainfo.xml /app/share/metainfo/$id.metainfo.xml
