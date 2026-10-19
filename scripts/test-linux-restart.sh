#!/bin/bash
# Real execv restart of the built Linux binary under Xvfb: same PID/argv/env, defaults kept, state lock re-acquired,
# and a failing exec target that leaves the original process, its lock and the state bytes untouched.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ ${1:-} != --inner ]]; then
    mkdir -p .build-linux/probes qa-state
    scripts/linux-build.sh build >.build-linux/probes/task11-restart-build.log 2>&1 || { tail -30 .build-linux/probes/task11-restart-build.log; exit 1; }
    rm -rf qa-state/task11-restart
    exec docker run --rm -v "$PWD:/work" -w /work -e GTK_A11Y=none -e GSK_RENDERER=cairo ytb-linux-dev bash -c '
        Xvfb :89 -screen 0 1280x1024x24 >/tmp/restart-xvfb.log 2>&1 & server=$!
        trap "kill $server 2>/dev/null || true" EXIT
        sleep .5
        DISPLAY=:89 dbus-run-session -- bash scripts/test-linux-restart.sh --inner'
fi

app=/work/.build-linux/debug/YugiTokenBar
fail() { echo "FAIL: $*"; exit 1; }
sha() { [[ -f $1 ]] && sha256sum "$1" | cut -d" " -f1 || echo absent; }
starttime() { awk '{print $22}' /proc/$1/stat; }
wait_for() { # file pattern seconds
    for _ in $(seq $(($3 * 10))); do grep -q "$2" "$1" 2>/dev/null && return 0; sleep .1; done
    return 1
}

run() { # name, extra env assignments...
    local name=$1; shift
    local root=/work/qa-state/task11-restart/$name
    mkdir -p "$root/home" "$root/config" "$root/state"
    printf '{"coins":123}' > "$root/state/state.json"
    local out=$root/out.log state_before; state_before=$(sha "$root/state/state.json")
    env HOME="$root/home" XDG_CONFIG_HOME="$root/config" XDG_DATA_HOME="$root/home/data" XDG_CACHE_HOME="$root/home/cache" \
        YTB_STATE_DIR="$root/state" YTB_SMOKE_RESTART=1 YTB_SMOKE_ENV_MARK=kept LANG=C.UTF-8 "$@" \
        stdbuf -oL "$app" >"$out" 2>&1 &
    pid=$!
    for _ in $(seq 100); do [[ $(tr '\0' ' ' </proc/$pid/cmdline 2>/dev/null) == *YugiTokenBar* ]] && break; sleep .1; done
    cmd_before=$(tr '\0' ' ' </proc/$pid/cmdline); start_before=$(starttime $pid); exe_before=$(readlink /proc/$pid/exe)
    echo "[$name] pid=$pid cmdline=$cmd_before"
    case $name in
    success)
        wait_for "$out" SMOKE_RESTART_OK 60 || { cat "$out"; fail "restarted image never reported SMOKE_RESTART_OK"; }
        kill -0 $pid 2>/dev/null || fail "pid $pid exited instead of exec-ing"
        [[ $(tr '\0' ' ' </proc/$pid/cmdline) == "$cmd_before" ]] || fail "cmdline changed"
        [[ $(starttime $pid) == "$start_before" ]] || fail "start time changed: the process was replaced, not exec-ed"
        [[ $(readlink /proc/$pid/exe) == "$exe_before" ]] || fail "executable changed"
        tr '\0' '\n' </proc/$pid/environ | grep -qx 'YTB_SMOKE_ENV_MARK=kept' || fail "environment not inherited"
        tr '\0' '\n' </proc/$pid/environ | grep -qx 'YTB_SMOKE_RESTARTED=1' || fail "restart marker missing"
        grep -q "SMOKE_RESTART_OK language=ja stored=ja" "$out" || fail "defaults did not survive exec"
        flock -n "$root/state/state.lock" true && fail "restarted image does not hold the state lock"
        ! grep -q SMOKE_RESTART_NO_MODEL "$out" || fail "state lock was not re-acquired"
        ! grep -q SMOKE_RESTART_FAILED "$out" || fail "exec reported failure"
        ;;
    failure)
        wait_for "$out" SMOKE_RESTART_FAILED_AGAIN 60 || { cat "$out"; fail "failed restart never reported"; }
        kill -0 $pid 2>/dev/null || fail "process died after a failed exec"
        [[ $(starttime $pid) == "$start_before" ]] || fail "process was replaced"
        flock -n "$root/state/state.lock" true && fail "state lock was released by the failed exec"
        grep -q "SMOKE_RESTART_FAILED error=.*No such file or directory" "$out" || fail "errno not reported"
        ! grep -q SMOKE_RESTART_OK "$out" || fail "restart unexpectedly succeeded"
        ;;
    esac
    local code=0
    timeout 60 tail --pid=$pid -f /dev/null || fail "app did not quit"
    wait $pid || code=$?
    [[ $code == 0 ]] || { cat "$out"; fail "exit code $code"; }
    [[ $(sha "$root/state/state.json") == "$state_before" ]] || fail "state.json bytes changed"
    echo "[$name] OK exit=0 state_sha=$(sha "$root/state/state.json" | cut -c1-12) $(grep -E 'SMOKE_' "$out" | tr '\n' ';')"
}

run success
run failure YTB_SMOKE_RESTART_EXEC=/nonexistent/yugitokenbar
echo "RESTART_QA_OK"
