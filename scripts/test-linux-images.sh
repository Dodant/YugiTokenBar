#!/bin/bash
# Display-backed native texture/loader tests; regular swift test skips this suite.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build-linux/probes/images qa-state/images
scripts/linux-build.sh test --skip 'LinuxImageTests' "$@"
docker run --rm \
    -v "$PWD:/work" -w /work \
    -e YTB_STATE_DIR=/work/qa-state/images \
    -e YTB_GTK_IMAGE_ARTIFACT_DIR=/work/.build-linux/probes/images \
    -e YTB_GTK_IMAGE_ONLINE="${YTB_GTK_IMAGE_ONLINE:-0}" \
    -e YTB_GTK_IMAGE_TESTS=1 -e GTK_A11Y=none -e GSK_RENDERER=cairo \
    ytb-linux-dev bash -c 'Xvfb :88 -screen 0 1280x1024x24 >/tmp/images-xvfb.log 2>&1 & server=$!; trap "kill $server 2>/dev/null || true" EXIT; sleep .5; DISPLAY=:88 dbus-run-session -- stdbuf -oL .build-linux/debug/YugiTokenBarTests-test-runner --testing-library swift-testing --filter LinuxImageTests'
