#!/bin/bash
# Shared launcher for the Linux GUI QA scripts (linux-smoke.sh, linux-scenarios.sh). Source it.
# Outer side: ytb_gui_container <script> <args...> builds the app and re-runs <script> --inner <args...>
# inside ytb-linux-dev under Xvfb 1280x1024 and a private D-Bus session.
# Inner side: ytb_launch / wait_for / wait_exit run the real binary with HOME, XDG_* and YTB_STATE_DIR under one run directory.

ytb_gui_container() {
    local script=$1; shift
    mkdir -p .build-linux/probes qa-state
    scripts/linux-build.sh build >.build-linux/probes/gui-build.log 2>&1 || { tail -30 .build-linux/probes/gui-build.log; exit 1; }
    exec docker run --rm -v "$PWD:/work" -w /work \
        -e GSK_RENDERER=cairo -e GDK_BACKEND=x11 -e GTK_A11Y=none -e LANG=C.UTF-8 \
        ytb-linux-dev bash -c '
            Xvfb :99 -screen 0 1280x1024x24 >/tmp/xvfb.log 2>&1 & server=$!
            trap "kill $server 2>/dev/null || true" EXIT
            for _ in $(seq 50); do [[ -S /tmp/.X11-unix/X99 ]] && break; sleep .1; done
            DISPLAY=:99 dbus-run-session -- bash "$@"' -- "$script" --inner "$@"
}

APP=/work/.build-linux/debug/YugiTokenBar
TOOL=/work/scripts/linux-smoke-tool.py
fail() { echo "FAIL: $*"; exit 1; }
sha() { [[ -f $1 ]] && sha256sum "$1" | cut -d" " -f1 || echo absent; }

wait_for() { # file pattern seconds
    for _ in $(seq $(($3 * 10))); do grep -q "$2" "$1" 2>/dev/null && return 0; sleep .1; done
    return 1
}

# ytb_launch <run dir> <log file> [VAR=value ...]: starts the app in the background, sets $pid. Never touches the real save.
# A non-empty $WRAP (e.g. "dbus-run-session --") prefixes the command; a second instance needs its own session bus,
# because on the same bus GApplication forwards it to the first instance instead of starting it.
ytb_launch() {
    local run=$1 log=$2; shift 2
    env HOME="$run/home" XDG_CONFIG_HOME="$run/config" XDG_DATA_HOME="$run/data" XDG_CACHE_HOME="$run/cache" \
        YTB_STATE_DIR="$run/state" CLAUDE_CONFIG_DIR="$run/claude" YTB_SMOKE_NO_IMAGES=1 "$@" ${WRAP:-} stdbuf -oL "$APP" >"$log" 2>&1 &
    pid=$!
}

# wait_exit <pid> <seconds>: sets $code to the exit status, fails when the process does not quit in time.
wait_exit() {
    timeout "$2" tail --pid="$1" -f /dev/null || { kill -9 "$1" 2>/dev/null || true; fail "pid $1 did not exit within $2 s"; }
    code=0; wait "$1" || code=$?
}
