#!/bin/bash
# Real sensitive GtkButton activation, model publication, rendered screens and persisted save parity (shop + dex + usage + settings).
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build-linux/probes/ui qa-state/ui
scripts/linux-build.sh test --filter 'LinuxModelTests|LinuxTransferTests|LinuxShopTests|LinuxDexTests|LinuxUsageTests|LinuxSettingsTests'
docker run --rm \
    -v "$PWD:/work" -w /work \
    -e YTB_STATE_DIR=/work/qa-state/ui \
    -e HOME=/work/qa-state/ui/home -e XDG_DATA_HOME=/work/qa-state/ui/data \
    -e XDG_CACHE_HOME=/work/qa-state/ui/cache -e XDG_CONFIG_HOME=/work/qa-state/ui/config \
    -e YTB_GTK_UI_ARTIFACT_DIR=/work/.build-linux/probes/ui \
    -e YTB_SMOKE_NO_IMAGES="${YTB_SMOKE_NO_IMAGES:-1}" \
    -e YTB_GTK_UI_TESTS=1 -e GTK_A11Y=none -e GSK_RENDERER=cairo \
    ytb-linux-dev bash -c 'mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME"; Xvfb :87 -screen 0 1280x1024x24 >/tmp/ui-xvfb.log 2>&1 & server=$!; trap "kill $server 2>/dev/null || true" EXIT; sleep .5; DISPLAY=:87 dbus-run-session -- stdbuf -oL .build-linux/debug/YugiTokenBarTests-test-runner --testing-library swift-testing --no-parallel --filter "LinuxShopTests|LinuxDexTests|LinuxUsageTests|LinuxSettingsTests"'
