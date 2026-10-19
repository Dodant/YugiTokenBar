#!/bin/bash
# Deterministic end-to-end smoke of the real Linux binary: for each screen it copies the test-only fixture into a new run
# directory, drives the real GTK widgets (YTB_SMOKE_SCREEN, LinuxSmokeDriver), captures <screen>.png with scrot and checks
# exit code 0, SMOKE_READY, a non-blank PNG and the saved state. Output: .build-linux/probes/smoke/<screen>.{png,log}, <screen>-state.json.
# Usage: scripts/linux-smoke.sh [shop|dex|open|usage|setting|all]
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/linux-gui-lib.sh
[[ ${1:-} == --inner ]] || ytb_gui_container scripts/linux-smoke.sh "$@"
shift

screens=${1:-all}
[[ $screens == all ]] && screens="shop dex open usage setting"
out=/work/.build-linux/probes/smoke
stamp=$(date +%Y%m%d-%H%M%S)-$$
mkdir -p "$out"

for screen in $screens; do
    run=/work/qa-state/smoke/$stamp/$screen
    rm -f "$out/$screen".png "$out/$screen".log "$out/$screen"-state.json   # only this screen: other screens' evidence stays
    python3 "$TOOL" prepare "$run" fixture
    ytb_launch "$run" "$out/$screen.log" YTB_SMOKE_SCREEN=$screen YTB_SMOKE_EXIT_MS=2500
    wait_for "$out/$screen.log" SMOKE_READY 60 || { cat "$out/$screen.log"; kill -9 $pid 2>/dev/null || true; fail "$screen: no SMOKE_READY"; }
    scrot -o "$out/$screen.png"
    wait_exit $pid 60
    [[ $code == 0 ]] || { cat "$out/$screen.log"; fail "$screen: exit code $code"; }
    ! grep -q SMOKE_FAIL "$out/$screen.log" || { cat "$out/$screen.log"; fail "$screen: SMOKE_FAIL"; }
    python3 "$TOOL" verify "$screen" "$run" "$out" || fail "$screen: result check"
    echo "[$screen] OK $(grep SMOKE_READY "$out/$screen.log")"
done
echo "SMOKE_OK $screens"
