#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"

ensure_directories
run_component "$ROOT/000-kernel/linux"
rm -rf -- "$EFILINUX_ROOTFS/usr/lib/firmware"
remove_rootfs_owner_prefix /usr/lib/firmware
run_component "$ROOT/000-kernel/linux-firmware"
run_component "$ROOT/000-kernel/sof-firmware"
run_component "$ROOT/000-kernel/wireless-regdb"
run_component "$ROOT/000-kernel/image"
