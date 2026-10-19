#!/bin/bash
# Installs the Flatpak bundle with `flatpak install --user` into a fresh HOME under qa-state/flatpak/<stamp>/ and checks it:
#   run    — libraries of /app/bin/YugiTokenBar (no missing, libswift*, libFoundation or SDK paths), resources only from
#            /app/share/yugitokenbar with no repository in the sandbox, then a real run under Xvfb that discovers synthetic
#            Claude/Codex logs at their default places, credits the first run and buys a pack (YTB_SMOKE_SCREEN=open).
#   portal — export → cancel → export → import of a Mac-style save through xdg-desktop-portal(-gtk) and the document portal,
#            driven with xdotool (needs xdotool, scrot and the portal daemons; the Debian ytb-flatpak-portal container).
# HOME, XDG_* and YTB_STATE_DIR all point into the run directory; the save lives in the sandbox's own data folder.
# Output: .build-linux/probes/flatpak/. Usage: scripts/test-flatpak.sh [run|portal] [bundle]
set -euo pipefail
cd "$(dirname "$0")/.."
id=io.github.dodant.YugiTokenBar
mode=${1:-run}
fail() { echo "FAIL: $*"; exit 1; }

if [[ $mode != _portal ]]; then
    version=$(awk '/^## [0-9]/{print $2; exit}' CHANGELOG.md)
    bundle=$(realpath "${2:-build/release/YugiTokenBar-$version-$(uname -m).flatpak}")
    export TOOL=$PWD/scripts/linux-smoke-tool.py OUT=$PWD/.build-linux/probes/flatpak
    export RUN=$PWD/qa-state/flatpak/$(date +%Y%m%d-%H%M%S)-$$-$mode
    export HOME=$RUN/home
    export XDG_DATA_HOME=$HOME/.local/share XDG_CONFIG_HOME=$HOME/.config XDG_CACHE_HOME=$HOME/.cache
    # The portals hand out $XDG_RUNTIME_DIR/doc paths that Flatpak mounts at /run/user/<uid>/doc in the sandbox, so the
    # runtime directory must be that one; the script runs in a throwaway container, never in a desktop session.
    export XDG_RUNTIME_DIR=/run/user/$(id -u)
    mkdir -p "$XDG_RUNTIME_DIR"; chmod 700 "$XDG_RUNTIME_DIR"
    export YTB_STATE_DIR=$HOME/.var/app/$id/data/YugiTokenBar
    export GSK_RENDERER=cairo GTK_A11Y=none LANG=C.UTF-8
    unset CLAUDE_CONFIG_DIR CODEX_HOME YTB_RESOURCES WAYLAND_DISPLAY
    mkdir -p "$OUT" "$HOME" "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
    python3 "$TOOL" flatpak-home "$HOME"
    flatpak install --user -y --noninteractive "$bundle"
    flatpak info --user --show-ref --show-commit $id

    display=:$((90 + RANDOM % 9))
    Xvfb "$display" -screen 0 1280x1024x24 >"$RUN/xvfb.log" 2>&1 & server=$!
    trap 'kill $server 2>/dev/null || true' EXIT
    for _ in $(seq 50); do [[ -S /tmp/.X11-unix/X${display#:} ]] && break; sleep .1; done
    export DISPLAY=$display
fi

case $mode in
run)
    flatpak run --command=sh $id -c 'ldd /app/bin/YugiTokenBar' | tee "$OUT/ldd.log"
    ! grep -E 'not found|/usr/lib/sdk/|libswift|libFoundation' "$OUT/ldd.log" || fail "unexpected dynamic library"
    echo LDD_OK
    # The binary's #filePath repository root and the host checkout must both be absent in the sandbox.
    flatpak run --command=sh $id -c '
        set -eu
        repo=$(grep -a -o "/[^[:cntrl:]\"]*/Sources/YugiTokenBar/AppInfo.swift" /app/bin/YugiTokenBar | head -1 || true)
        [ -n "$repo" ] || { echo "no compiled repository path in the binary"; exit 1; }
        echo "COMPILED_REPO_ROOT ${repo%/Sources/*}"
        test ! -e "${repo%/Sources/*}"
        test ! -e '"$PWD"'/Sources
        test -z "${YTB_RESOURCES:-}"
        ls /app/share/yugitokenbar /app/share/yugitokenbar/licenses
        echo "VERSION_TXT $(cat /app/share/yugitokenbar/version.txt)"
        if [ -w "$HOME" ]; then echo "HOME is writable in the sandbox"; exit 1; fi
        echo HOME_READ_ONLY
        echo "SANDBOX_XDG data=$XDG_DATA_HOME config=$XDG_CONFIG_HOME cache=$XDG_CACHE_HOME"
        echo SANDBOX_NO_REPO' | tee "$OUT/sandbox.log"
    grep -q SANDBOX_NO_REPO "$OUT/sandbox.log" || fail "sandbox check"

    YTB_SMOKE_SCREEN=open YTB_SMOKE_EXIT_MS=1500 timeout 180 dbus-run-session -- flatpak run $id >"$OUT/run.log" 2>&1 || {
        code=$?; cat "$OUT/run.log"; fail "app exit code $code"; }
    cat "$OUT/run.log"
    grep -q 'SMOKE_READY screen=open' "$OUT/run.log" || fail "no SMOKE_READY"
    ! grep -q SMOKE_FAIL "$OUT/run.log" || fail SMOKE_FAIL
    python3 "$TOOL" expect-flatpak-purchase "$YTB_STATE_DIR" | tee -a "$OUT/run.log"
    cp "$YTB_STATE_DIR/state.json" "$OUT/run-state.json"
    echo "XDG writes:" >>"$OUT/run.log"
    (cd "$HOME/.var/app/$id" && find . -type f | sort) | tee -a "$OUT/run.log"
    echo "FLATPAK_RUN_OK $(flatpak info --user --show-ref $id)"
    ;;
portal)
    for tool in xdotool scrot /usr/libexec/xdg-desktop-portal /usr/libexec/xdg-desktop-portal-gtk /usr/libexec/xdg-document-portal; do
        command -v "$tool" >/dev/null || fail "$tool missing: run this in the ytb-flatpak-portal container"
    done
    mkdir -p "$XDG_CONFIG_HOME/xdg-desktop-portal" "$HOME/Exports"
    printf '[preferred]\ndefault=gtk\n' >"$XDG_CONFIG_HOME/xdg-desktop-portal/portals.conf"
    python3 "$TOOL" envelope "$HOME/mac-save.json"
    # The session bus activates xdg-desktop-portal, -gtk and the document portal on demand, as on a desktop.
    ! mountpoint -q "$XDG_RUNTIME_DIR/doc" || fail "a document portal is already mounted at $XDG_RUNTIME_DIR/doc"
    code=0; dbus-run-session -- bash "$0" _portal 2>"$OUT/portal-daemons.log" || code=$?
    fusermount3 -u "$XDG_RUNTIME_DIR/doc" 2>/dev/null || true
    exit $code
    ;;
_portal)
    log=$OUT/portal.log; : >"$log"
    note() { echo "$(date +%T.%N | cut -c1-12) $*" | tee -a "$log"; }
    shot() { scrot -o "$OUT/portal-$1.png"; note "PNG portal-$1.png"; }
    app_window() { xdotool search --onlyvisible --name '^YugiTokenBar$' 2>/dev/null | head -1; }
    dialog_window() { # waits for a visible window that is not the app window
        for _ in $(seq 150); do
            local id; id=$(xdotool search --onlyvisible --name . 2>/dev/null | grep -vx "$main" | tail -1 || true)
            [[ -n $id ]] && { echo "$id"; return 0; }; sleep .2
        done; return 1
    }
    dialog_gone() { for _ in $(seq 50); do [[ -z $(xdotool search --onlyvisible --name . 2>/dev/null | grep -vx "$main") ]] && return 0; sleep .2; done; return 1; }
    click() { xdotool mousemove --sync "$1" "$2" click 1; }
    # Button centres in the 1280x1000 window (portal-settings.png, portal-import-confirm.png)
    export_button=${YTB_QA_EXPORT_XY:-346 549} import_button=${YTB_QA_IMPORT_XY:-441 549} confirm_button=${YTB_QA_CONFIRM_XY:-580 567}

    YTB_SMOKE_SCREEN=setting YTB_SMOKE_EXIT_MS=500 YTB_SMOKE_QUIT_FILE=$HOME/quit flatpak run $id >"$OUT/portal-app.log" 2>&1 & app=$!
    trap 'kill $app 2>/dev/null || true' EXIT
    for _ in $(seq 600); do grep -q SMOKE_READY "$OUT/portal-app.log" && break; sleep .1; done
    grep -q SMOKE_READY "$OUT/portal-app.log" || { cat "$OUT/portal-app.log"; fail "app not ready"; }
    main=$(app_window); [[ -n $main ]] || fail "no app window"
    xdotool windowmove --sync "$main" 0 0 windowsize --sync "$main" 1280 1000
    sleep 1; shot settings
    cp "$YTB_STATE_DIR/state.json" "$OUT/portal-before.json"

    # 1. Export, cancelled in the portal dialog: nothing is written.
    click $export_button
    dialog=$(dialog_window) || { shot no-dialog; fail "export: no portal dialog"; }
    note "EXPORT_DIALOG $(xdotool getwindowname "$dialog")"; sleep 1; shot export-dialog
    xdotool windowfocus --sync "$dialog" key Escape
    dialog_gone || fail "cancel: dialog stayed"
    sleep 1
    [[ -z $(find "$HOME/Exports" -type f) ]] || fail "cancel wrote a file"
    note EXPORT_CANCEL_OK

    # 2. Export to a folder of the read-only home: the document portal grants the write.
    click $export_button
    dialog=$(dialog_window) || fail "export again: no portal dialog"
    xdotool windowfocus --sync "$dialog" key ctrl+a type --delay 20 "$HOME/Exports/exported.json"
    sleep .5; shot export-named
    xdotool key Return
    dialog_gone || { shot export-stuck; fail "export: dialog stayed"; }
    for _ in $(seq 50); do [[ -s $HOME/Exports/exported.json ]] && break; sleep .2; done
    shot export-result
    python3 "$TOOL" expect-export "$HOME/Exports/exported.json" "$YTB_STATE_DIR" | tee -a "$log"
    # The sandbox sees HOME read-only, so the write can only have gone through a document-portal entry.
    note "DOC_PORTAL entries: $(ls "$XDG_RUNTIME_DIR/doc" | tr '\n' ' ')"
    shot exported

    # 3. Import the Mac-style envelope, then confirm in the app's dialog.
    click $import_button
    dialog=$(dialog_window) || fail "import: no portal dialog"
    note "IMPORT_DIALOG $(xdotool getwindowname "$dialog")"
    xdotool windowfocus --sync "$dialog" key ctrl+l type --delay 20 "$HOME/mac-save.json"
    sleep .5; shot import-dialog
    xdotool key Return
    sleep 2; shot import-confirm
    click $confirm_button
    sleep 2; shot imported
    python3 "$TOOL" expect-import "$YTB_STATE_DIR" "$OUT/portal-before.json" | tee -a "$log"

    touch "$HOME/quit"
    timeout 60 tail --pid=$app -f /dev/null || fail "app did not quit"
    code=0; wait $app || code=$?
    [[ $code == 0 ]] || { cat "$OUT/portal-app.log"; fail "exit code $code"; }
    note "PORTAL_ROUNDTRIP_OK"
    ;;
*) fail "usage: scripts/test-flatpak.sh [run|portal] [bundle]" ;;
esac
