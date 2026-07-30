#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/composer.sh"

profile="$ROOT/profiles/utils-zxmod.packages"

if [[ ${1:-} == --internal-extend ]]; then
    [[ $# == 1 ]] || die "unexpected internal composer arguments"
    compose_extend_profile "$profile"
    exit 0
fi

[[ $# == 0 ]] || die "usage: $0"
require_command fakeroot
[[ -f "$EFILINUX_ROOTFS_FAKEROOT_STATE" ]] || die 'rootfs fakeroot state is missing'
state_temporary="$EFILINUX_ROOTFS_FAKEROOT_STATE.tmp.$$"
rm -f -- "$state_temporary"
fakeroot -i "$EFILINUX_ROOTFS_FAKEROOT_STATE" -s "$state_temporary" -- \
    "$0" --internal-extend
mv -- "$state_temporary" "$EFILINUX_ROOTFS_FAKEROOT_STATE"
