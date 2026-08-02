#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

require_command readelf
rootfs=$EFILINUX_ROOTFS
loader="$rootfs/usr/lib/ld-linux-x86-64.so.2"

for name in xarchiver efilinux-live-manager; do
    application="$rootfs/usr/bin/$name"
    [[ -x $application ]] || die "desktop application is missing: $name"
    while IFS= read -r needed; do
        [[ -e "$rootfs/usr/lib/$needed" ]] || \
            die "desktop application ELF dependency is outside target rootfs: $name needs $needed"
    done < <(LC_ALL=C readelf -d "$application" |
        awk '/NEEDED/ { gsub(/\[|\]/, "", $NF); print $NF }')
done

manager_result=$(
    "$loader" --library-path "$rootfs/usr/lib" \
        "$rootfs/usr/bin/efilinux-live-manager" --self-test
)
[[ $manager_result == EFILINUX_LIVE_MANAGER_SELF_TEST_OK ]] ||
    die "EFI Linux Live Manager failed its target-runtime model test"

for resource in \
    /usr/share/applications/efilinux-live-manager.desktop \
    /usr/share/icons/hicolor/scalable/apps/efilinux-live-manager.svg \
    /usr/share/polkit-1/actions/org.efilinux.live-manager.policy; do
    [[ $(stat -c %a "$rootfs$resource") == 644 ]] ||
        die "EFI Linux Live Manager resource is not world-readable: $resource"
done

log "Desktop application ELF closure and Live Manager runtime checks passed"
