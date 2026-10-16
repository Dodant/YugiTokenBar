#!/bin/bash
# Run Swift 6.4.1 in Docker. Linux output and package pins stay in .build-linux/.
set -euo pipefail
cd "$(dirname "$0")/.."

image=ytb-linux-dev
docker image inspect "$image" >/dev/null 2>&1 || docker build -t "$image" -f docker/linux-dev.Dockerfile docker
mkdir -p .build-linux qa-state

subcommand=${1:-build}
if [[ $# -gt 0 ]]; then shift; fi

# SwiftPM replaces Package.resolved atomically. Keep the container's package
# root writable, rather than bind-mounting the lock file over the Mac lock.
exec docker run --rm \
    -v "$PWD/Package.swift:/work/Package.swift:ro" \
    -v "$PWD/Sources:/work/Sources:ro" \
    -v "$PWD/Tests:/work/Tests:ro" \
    -v "$PWD/Resources:/work/Resources:ro" \
    -v "$PWD/CHANGELOG.md:/work/CHANGELOG.md:ro" \
    -v "$PWD/CHANGELOG.en.md:/work/CHANGELOG.en.md:ro" \
    -v "$PWD/CHANGELOG.ja.md:/work/CHANGELOG.ja.md:ro" \
    -v "$PWD/.build-linux:/work/.build-linux" \
    -v "$PWD/qa-state:/work/qa-state" \
    -e YTB_STATE_DIR=/work/qa-state \
    -w /work "$image" bash -c '
        if [[ -f .build-linux/Package.resolved ]]; then
            cp .build-linux/Package.resolved Package.resolved
        fi
        trap '\''if [[ -f Package.resolved ]]; then cp Package.resolved .build-linux/Package.resolved; fi'\'' EXIT
        subcommand=$1
        shift
        swift "$subcommand" --scratch-path .build-linux "$@"
    ' -- "$subcommand" "$@"
