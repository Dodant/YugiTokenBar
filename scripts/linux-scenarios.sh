#!/bin/bash
# Behaviour scenarios on the real Linux binary under Xvfb: first-run credit, save failure and retry, state lock, newer schema.
# Exec restart stays in scripts/test-linux-restart.sh; the import race is covered by LinuxTransferTests.
# Output: .build-linux/probes/scenarios/. Usage: scripts/linux-scenarios.sh [first-run|save-failure|lock|schema|all]
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/linux-gui-lib.sh
[[ ${1:-} == --inner ]] || ytb_gui_container scripts/linux-scenarios.sh "$@"
shift

out=/work/.build-linux/probes/scenarios
root=/work/qa-state/scenarios/$(date +%Y%m%d-%H%M%S)-$$
mkdir -p "$out"

visible_window() { # [id to ignore]: waits for a mapped YugiTokenBar window other than the ignored one, prints its id
    for _ in $(seq 300); do
        local id; id=$(xdotool search --onlyvisible --name '^YugiTokenBar$' 2>/dev/null | grep -vx "${1:-none}" | head -1 || true)
        [[ -n $id ]] && { echo "$id"; return 0; }
        sleep .1
    done
    return 1
}

first_run() {
    local run=$root/first-run; rm -rf "$run"
    python3 "$TOOL" prepare "$run" first-run
    ytb_launch "$run" "$out/first-run.log" YTB_SMOKE_SCREEN=shop YTB_SMOKE_EXIT_MS=500
    wait_for "$out/first-run.log" SMOKE_READY 60 || { cat "$out/first-run.log"; fail "first-run: no SMOKE_READY"; }
    wait_exit $pid 60
    [[ $code == 0 ]] || fail "first-run: exit code $code"
    python3 "$TOOL" expect-first-run "$run" "$out/first-run-state.json"
}

save_failure() {
    local run=$root/save-failure; rm -rf "$run"
    python3 "$TOOL" prepare "$run" fixture
    mkdir -p "$run/control"
    ytb_launch "$run" "$out/save-failure.log" YTB_SMOKE_SCENARIO=save-failure YTB_SMOKE_CONTROL="$run/control" YTB_SMOKE_EXIT_MS=300
    wait_for "$out/save-failure.log" SMOKE_READY 60 || { cat "$out/save-failure.log"; fail "save-failure: no SMOKE_READY"; }
    # Running as root ignores directory permissions, so a directory in place of state.json blocks the atomic write instead.
    mv "$run/state/state.json" "$run/hold.json"; mkdir "$run/state/state.json"
    touch "$run/control/blocked"
    wait_for "$out/save-failure.log" SMOKE_QUIT_REFUSED 30 || { cat "$out/save-failure.log"; fail "save-failure: close was not refused"; }
    grep -q SMOKE_DIRTY "$out/save-failure.log" || fail "save-failure: no dirty banner"
    sleep 1; kill -0 $pid 2>/dev/null || fail "save-failure: app exited while the save was failing"
    scrot -o "$out/save-failure-dirty.png"
    [[ -d $run/state/state.json ]] || fail "save-failure: block disappeared"
    rmdir "$run/state/state.json"; mv "$run/hold.json" "$run/state/state.json"
    touch "$run/control/unblocked"
    wait_exit $pid 60
    [[ $code == 0 ]] || { cat "$out/save-failure.log"; fail "save-failure: exit code $code"; }
    grep -q SMOKE_RETRIED "$out/save-failure.log" || fail "save-failure: retry button did not save"
    ! grep -q SMOKE_FAIL "$out/save-failure.log" || { cat "$out/save-failure.log"; fail "save-failure: SMOKE_FAIL"; }
    python3 "$TOOL" expect "$run" coins 1500
    python3 "$TOOL" state "$run" "$out/save-failure-state.json"
    echo "SAVE_FAILURE_OK"
}

lock() {
    local run=$root/lock; rm -rf "$run"
    python3 "$TOOL" prepare "$run" fixture
    local before; before=$(sha "$run/state/state.json")
    ytb_launch "$run" "$out/lock-first.log" YTB_SMOKE_SCREEN=shop YTB_SMOKE_EXIT_MS=12000
    local first=$pid
    wait_for "$out/lock-first.log" SMOKE_READY 60 || { cat "$out/lock-first.log"; fail "lock: first instance not ready"; }
    local first_window; first_window=$(visible_window) || fail "lock: first instance showed no window"
    WRAP="dbus-run-session --" ytb_launch "$run" "$out/lock-second.log"
    local second=$pid win
    win=$(visible_window "$first_window") || fail "lock: second instance showed no window"
    sleep 1.5
    kill -0 $second 2>/dev/null || fail "lock: second instance exited before the startup dialog was answered"
    scrot -o "$out/lock-dialog.png"
    xdotool windowfocus "$win" key Return
    wait_exit $second 30
    [[ $code == 0 ]] || { cat "$out/lock-second.log"; fail "lock: second instance exit code $code"; }
    kill -0 $first 2>/dev/null || fail "lock: first instance died"
    wait_exit $first 60
    [[ $code == 0 ]] || fail "lock: first instance exit code $code"
    [[ $(sha "$run/state/state.json") == "$before" ]] || fail "lock: state.json changed"
    python3 "$TOOL" state "$run" "$out/lock-state.json"
    echo "LOCK_OK"
}

schema() {
    local run=$root/schema; rm -rf "$run"
    mkdir -p "$run/home" "$run/state" "$run/config" "$run/data" "$run/cache"
    printf '{"schema":2,"coins":7}' > "$run/state/state.json"
    local before; before=$(sha "$run/state/state.json")
    ytb_launch "$run" "$out/schema.log"
    local win; win=$(visible_window) || fail "schema: no window"
    sleep 1.5
    kill -0 $pid 2>/dev/null || fail "schema: app exited before the dialog was answered"
    scrot -o "$out/schema-dialog.png"
    xdotool windowfocus "$win" key Return
    wait_exit $pid 30
    [[ $code == 0 ]] || { cat "$out/schema.log"; fail "schema: exit code $code"; }
    [[ $(sha "$run/state/state.json") == "$before" ]] || fail "schema: state.json bytes changed"
    [[ $(ls -A "$run/state" | grep -v '^state.lock$' | tr '\n' ' ') == "state.json " ]] || fail "schema: extra files in the state directory: $(ls -A "$run/state")"
    echo "SCHEMA_OK sha=${before:0:12}"
}

scenario=${1:-all}
if [[ $scenario == all ]]; then
    first_run; save_failure; lock; schema
else
    "${scenario//-/_}"
fi
echo "SCENARIOS_OK $scenario"
