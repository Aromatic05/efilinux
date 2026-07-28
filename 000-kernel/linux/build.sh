#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

require_command curl tar make gcc bc bison flex perl openssl md5sum
ensure_directories

archive="$EFILINUX_DOWNLOADS/linux-$LINUX_VERSION.tar.xz"
source_directory="$EFILINUX_BUILD/sources/linux-$LINUX_VERSION-kernel"

[[ -d "$EFILINUX_TARGET/rootfs" ]] || die "target rootfs has not been built"
[[ -f "$EFILINUX_INITRAMFS_DEVICES" ]] || \
    die "initramfs device manifest has not been built"

download \
    "https://www.kernel.org/pub/linux/kernel/v${LINUX_VERSION%%.*}.x/linux-$LINUX_VERSION.tar.xz" \
    "$archive"
verify_md5 "$LINUX_MD5" "$archive"
extract_source "$archive" "$source_directory"
reset_directory "$EFILINUX_KERNEL_BUILD"

log "Configuring EFI-stub kernel"
make -C "$source_directory" O="$EFILINUX_KERNEL_BUILD" x86_64_defconfig

scripts_config="$source_directory/scripts/config"
"$scripts_config" --file "$EFILINUX_KERNEL_BUILD/.config" \
    --enable EFI \
    --enable EFI_STUB \
    --enable BLK_DEV_INITRD \
    --enable DEVTMPFS \
    --enable DEVTMPFS_MOUNT \
    --enable TMPFS \
    --enable PROC_FS \
    --enable SYSFS \
    --enable TTY \
    --enable UNIX98_PTYS \
    --enable SERIAL_8250 \
    --enable SERIAL_8250_CONSOLE \
    --enable BINFMT_ELF \
    --enable BINFMT_SCRIPT \
    --enable RD_GZIP \
    --enable CMDLINE_BOOL \
    --set-str INITRAMFS_SOURCE "$EFILINUX_TARGET/rootfs $EFILINUX_INITRAMFS_DEVICES" \
    --set-str CMDLINE "console=tty0 console=ttyS0,115200 rdinit=/init"

make -C "$source_directory" O="$EFILINUX_KERNEL_BUILD" olddefconfig

log "Building EFI-stub kernel with embedded initramfs"
make -C "$source_directory" O="$EFILINUX_KERNEL_BUILD" \
    -j"$EFILINUX_JOBS" bzImage

mkdir -p "$EFILINUX_EFI_DIR/EFI/BOOT"
cp "$EFILINUX_KERNEL_BUILD/arch/x86/boot/bzImage" \
    "$EFILINUX_EFI_DIR/EFI/BOOT/BOOTX64.EFI"
