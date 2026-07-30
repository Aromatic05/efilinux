#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/composer.sh"

kernel_profile="$ROOT/profiles/kernel.packages"
manifest_generator="$ROOT/000-kernel/image/gen_initramfs_manifest.py"
efi_image="$EFILINUX_EFI_DIR/EFI/BOOT/BOOTX64.EFI"
linux_metadata=$("$ROOT/000-kernel/linux/build.sh" --print-metadata)
read -r linux_version linux_recipe_key < <(
    python3 -c 'import json,sys; data=json.load(sys.stdin); print(data["pkgver"], data["recipe_key"])' \
        <<<"$linux_metadata"
)
kernel_state="$EFILINUX_BUILD/kernel-state/$linux_recipe_key"

if [[ ${1:-} == --internal-extend ]]; then
    [[ $# == 1 ]] || die "unexpected internal kernel composer arguments"
    compose_extend_profile "$kernel_profile"
    exit 0
fi

[[ $# == 0 ]] || die "usage: $0"
require_command fakeroot install make python3 zstd
ensure_directories

[[ -d "$EFILINUX_ROOTFS" ]] || die "rootfs has not been composed"
[[ -f "$EFILINUX_ROOTFS_FAKEROOT_STATE" ]] || \
    die "rootfs fakeroot metadata has not been built"
[[ -d "$kernel_state/source" && -d "$kernel_state/build" ]] || \
    die "linux link state is missing for recipe key $linux_recipe_key"

state_temporary="$EFILINUX_ROOTFS_FAKEROOT_STATE.tmp.$$"
rm -f "$state_temporary"
fakeroot \
    -i "$EFILINUX_ROOTFS_FAKEROOT_STATE" \
    -s "$state_temporary" -- \
    "$0" --internal-extend
mv "$state_temporary" "$EFILINUX_ROOTFS_FAKEROOT_STATE"

fakeroot -i "$EFILINUX_ROOTFS_FAKEROOT_STATE" -- \
    python3 "$manifest_generator" \
        --rootfs "$EFILINUX_ROOTFS" \
        --output "$EFILINUX_INITRAMFS_MANIFEST"

kernel_source_directory="$kernel_state/source"
kernel_build_directory="$kernel_state/build"
kernel_config_fragment="$kernel_state/common-pc.config"
kernel_config_validator="$kernel_state/validate_config.py"
source "$kernel_state/kernel-common.sh"
source "$ROOT/000-kernel/image/common.sh"

configure_embedded_initramfs "$EFILINUX_INITRAMFS_MANIFEST"
remove_embedded_initramfs_outputs "$kernel_build_directory"

log "Linking final EFILinux EFI executable with the composed rootfs"
ZSTD_NBTHREADS="${EFILINUX_COMPRESSION_JOBS:-16}" \
ZSTD="zstd -T${EFILINUX_COMPRESSION_JOBS:-16}" \
    kernel_make -C "$kernel_source_directory" O="$kernel_build_directory" \
        -j"$EFILINUX_JOBS" bzImage

mkdir -p "$(dirname -- "$efi_image")"
install -m0644 \
    "$kernel_build_directory/arch/x86/boot/bzImage" \
    "$efi_image"
log "Created $efi_image with Linux $linux_version"
