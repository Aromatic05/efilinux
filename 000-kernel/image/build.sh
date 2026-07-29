#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/000-kernel/linux/common.sh"

require_command bc bison curl flex gcc make md5sum openssl perl python3
ensure_directories

initramfs_tree="$EFILINUX_ROOTFS"
efi_image="$EFILINUX_EFI_DIR/EFI/BOOT/BOOTX64.EFI"

[[ -d "$initramfs_tree" ]] || die "initramfs tree has not been built"
[[ -f "$EFILINUX_INITRAMFS_DEVICES" ]] || \
    die "initramfs device manifest has not been built"

ensure_clean_kernel_build_tree
configure_embedded_initramfs "$initramfs_tree" "$EFILINUX_INITRAMFS_DEVICES"
remove_embedded_initramfs_outputs "$EFILINUX_KERNEL_BUILD"

log "Building final EFILinux EFI executable"
ZSTD_NBTHREADS="${EFILINUX_COMPRESSION_JOBS:-16}" \
make -C "$kernel_source_directory" O="$EFILINUX_KERNEL_BUILD" \
    -j"$EFILINUX_JOBS" bzImage

mkdir -p "$(dirname -- "$efi_image")"
install -m 0644 \
    "$EFILINUX_KERNEL_BUILD/arch/x86/boot/bzImage" \
    "$efi_image"
