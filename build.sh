#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")" && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

"$ROOT/preflight.sh"
ensure_directories

recipe_session_owner=false
if [[ -z ${EFILINUX_RECIPE_SESSION_DIR:-} ]]; then
    mkdir -p "$EFILINUX_BUILD/recipe-sessions"
    EFILINUX_RECIPE_SESSION_DIR="$EFILINUX_BUILD/recipe-sessions/build-$$-$RANDOM"
    (umask 077; mkdir "$EFILINUX_RECIPE_SESSION_DIR")
    export EFILINUX_RECIPE_SESSION_DIR
    recipe_session_owner=true
fi
cleanup_recipe_session() {
    [[ $recipe_session_owner == true ]] || return
    rm -rf -- "$EFILINUX_RECIPE_SESSION_DIR"
}
trap cleanup_recipe_session EXIT

# The final EFI-stub kernel embeds the initramfs, so runtime is staged first.
run_component "$ROOT/001-runtime"
run_component "$ROOT/002-system"
run_component "$ROOT/003-graphical"
run_component "$ROOT/004-desktop"
run_component "$ROOT/005-utils"
run_component "$ROOT/005-applications"
run_component "$ROOT/000-kernel"

log "Build complete"
printf 'EFI executable: %s\n' "$EFILINUX_EFI_DIR/EFI/BOOT/BOOTX64.EFI"
printf 'Target rootfs:  %s\n' "$EFILINUX_ROOTFS"
