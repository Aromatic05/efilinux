#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

require_command readelf
rootfs=$EFILINUX_ROOTFS
application="$rootfs/usr/bin/xarchiver"

[[ -x $application ]] || die "desktop application is missing: xarchiver"
while IFS= read -r needed; do
    [[ -e "$rootfs/usr/lib/$needed" ]] || \
        die "desktop application ELF dependency is outside target rootfs: xarchiver needs $needed"
done < <(readelf -d "$application" | awk '/NEEDED/ { gsub(/\[|\]/, "", $NF); print $NF }')

log "Desktop application ELF closure check passed"
