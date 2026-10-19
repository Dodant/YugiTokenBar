#!/bin/bash
# Builds the Linux Flatpak bundle build/release/YugiTokenBar-<version>-<arch>.flatpak from packaging/io.github.dodant.YugiTokenBar.json
# against the verified Linux lock (.build-linux/Package.resolved, or YTB_LINUX_LOCK) and appends it to build/release/SHA256SUMS.
# Runs where flatpak-builder runs as root: the privileged ytb-sdk-recovery:gnome50 container locally, the gnome-50 container in CI.
# Log: .build-linux/probes/flatpak/build-<arch>.log. Usage: scripts/build-flatpak.sh [--arch x86_64|aarch64]
set -euo pipefail
cd "$(dirname "$0")/.."

arch=$(uname -m)
if [[ ${1:-} == --arch ]]; then arch=$2; fi
[[ $arch == x86_64 || $arch == aarch64 ]] || { echo "Unsupported arch $arch" >&2; exit 1; }
id=io.github.dodant.YugiTokenBar
lock=${YTB_LINUX_LOCK:-.build-linux/Package.resolved}
[[ -f $lock ]] || { echo "Linux lock $lock missing (run scripts/linux-build.sh build first)" >&2; exit 1; }
version=$(awk '/^## [0-9]/{print $2; exit}' CHANGELOG.md)
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid CHANGELOG version' >&2; exit 1; }

mkdir -p .build-linux/probes/flatpak build/release build/flatpak/$arch
exec > >(tee ".build-linux/probes/flatpak/build-$arch.log") 2>&1

before=$(sha256sum "$lock" | cut -d' ' -f1)
echo "LINUX_LOCK $lock sha256=$before"
cp "$lock" build/flatpak/Package.resolved

# The SDK, Platform and Swift extension come from Flathub when the container does not have them yet.
for ref in org.gnome.Sdk//50 org.gnome.Platform//50 org.freedesktop.Sdk.Extension.swift6//25.08; do
    flatpak info "$ref" >/dev/null 2>&1 || flatpak install -y --noninteractive --system flathub "$ref"
done
flatpak --version
flatpak-builder --version
for ref in org.gnome.Sdk//50 org.gnome.Platform//50 org.freedesktop.Sdk.Extension.swift6//25.08; do
    echo "RUNTIME $(flatpak info --show-ref "$ref") commit=$(flatpak info --show-commit "$ref")"
done

flatpak-builder --arch="$arch" --force-clean --disable-rofiles-fuse \
    --state-dir="build/flatpak/$arch/state" --repo="build/flatpak/$arch/repo" \
    "build/flatpak/$arch/app" packaging/$id.json

after=$(sha256sum "$lock" | cut -d' ' -f1)
echo "LINUX_LOCK after sha256=$after"
[[ $before == "$after" ]] || { echo "Linux lock changed during the build" >&2; exit 1; }
cmp -s "$lock" build/flatpak/Package.resolved || { echo 'Builder copy of the lock differs from the verified lock' >&2; exit 1; }

bundle=YugiTokenBar-$version-$arch.flatpak
flatpak build-bundle --arch="$arch" --runtime-repo=https://dl.flathub.org/repo/flathub.flatpakrepo "build/flatpak/$arch/repo" "build/release/$bundle" $id
touch build/release/SHA256SUMS
grep -v " $bundle\$" build/release/SHA256SUMS > build/release/SHA256SUMS.new || true
(cd build/release && sha256sum "$bundle") >> build/release/SHA256SUMS.new
mv build/release/SHA256SUMS.new build/release/SHA256SUMS
echo "BUNDLE build/release/$bundle $(stat -c%s "build/release/$bundle") bytes"
cat build/release/SHA256SUMS
