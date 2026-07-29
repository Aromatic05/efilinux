#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")" && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

"$ROOT/preflight.sh"
ensure_directories

# The final EFI-stub kernel embeds the initramfs, so runtime is staged first.
run_component "$ROOT/001-runtime"
run_component "$ROOT/002-system"
run_component "$ROOT/003-graphical"
run_component "$ROOT/000-kernel"

log "Build complete"
printf 'EFI executable: %s\n' "$EFILINUX_EFI_DIR/EFI/BOOT/BOOTX64.EFI"
printf 'Target rootfs:  %s\n' "$EFILINUX_ROOTFS"
