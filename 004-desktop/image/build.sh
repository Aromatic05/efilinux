#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/composer.sh"

profile="$ROOT/profiles/desktop.packages"

if [[ ${1:-} == --internal-compose ]]; then
    [[ $# == 1 ]] || die "unexpected internal composer arguments"
    compose_profile "$profile"
    exit 0
fi

[[ $# == 0 ]] || die "usage: $0"
require_command fakeroot
ensure_directories
mkdir -p "$EFILINUX_STATE"
state_temporary="$EFILINUX_ROOTFS_FAKEROOT_STATE.tmp.$$"
rm -f -- "$state_temporary"
fakeroot -s "$state_temporary" -- "$0" --internal-compose
mv -- "$state_temporary" "$EFILINUX_ROOTFS_FAKEROOT_STATE"
log "Saved rootfs fakeroot metadata to $EFILINUX_ROOTFS_FAKEROOT_STATE"
