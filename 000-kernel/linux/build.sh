#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

require_command curl tar make gcc bc bison flex perl python3 openssl md5sum depmod strip zstd
ensure_directories

mode=${1:-}
archive="$EFILINUX_DOWNLOADS/linux-$LINUX_VERSION.tar.xz"
source_directory="$EFILINUX_BUILD/sources/linux-$LINUX_VERSION-kernel"
rootfs_directory="$EFILINUX_ROOTFS"
module_directory="$rootfs_directory/usr/lib/modules/$LINUX_VERSION"
config_fragment="$ROOT/000-kernel/linux/common-pc.config"

[[ -d "$rootfs_directory" ]] || die "target runtime rootfs has not been built"
[[ -f "$EFILINUX_INITRAMFS_DEVICES" ]] || \
    die "initramfs device manifest has not been built"

configure_kernel() {
    download \
        "https://www.kernel.org/pub/linux/kernel/v${LINUX_VERSION%%.*}.x/linux-$LINUX_VERSION.tar.xz" \
        "$archive"
    verify_md5 "$LINUX_MD5" "$archive"
    extract_source "$archive" "$source_directory"
    reset_directory "$EFILINUX_KERNEL_BUILD"

    log "Configuring curated common-PC kernel"
    make -C "$source_directory" O="$EFILINUX_KERNEL_BUILD" tinyconfig
    "$source_directory/scripts/kconfig/merge_config.sh" \
        -m \
        -O "$EFILINUX_KERNEL_BUILD" \
        "$EFILINUX_KERNEL_BUILD/.config" \
        "$config_fragment"

    local scripts_config="$source_directory/scripts/config"
    "$scripts_config" --file "$EFILINUX_KERNEL_BUILD/.config" \
        --enable CMDLINE_BOOL \
        --set-str CMDLINE "console=tty0 console=ttyS0,115200 rdinit=/init"
    make -C "$source_directory" O="$EFILINUX_KERNEL_BUILD" olddefconfig
    make -C "$source_directory" O="$EFILINUX_KERNEL_BUILD" prepare
    python3 "$ROOT/000-kernel/linux/validate_config.py" \
        "$config_fragment" \
        "$EFILINUX_KERNEL_BUILD/.config"
}

build_modules() {
    configure_kernel

    log "Building kernel symbols and curated common-PC modules"
    make -C "$source_directory" O="$EFILINUX_KERNEL_BUILD" \
        -j"$EFILINUX_JOBS" vmlinux modules

    rm -rf "$module_directory"
    mkdir -p "$(dirname -- "$module_directory")"
    make -C "$source_directory" O="$EFILINUX_KERNEL_BUILD" \
        INSTALL_MOD_PATH="$rootfs_directory" \
        MODLIB="$module_directory" \
        INSTALL_MOD_STRIP=1 \
        modules_install
    rm -f "$module_directory/build" "$module_directory/source"
    depmod -b "$rootfs_directory" "$LINUX_VERSION"
}

build_efi() {
    [[ -f "$EFILINUX_KERNEL_BUILD/.config" ]] || \
        die "kernel modules must be built before the EFI image"

    local scripts_config="$source_directory/scripts/config"
    "$scripts_config" --file "$EFILINUX_KERNEL_BUILD/.config" \
        --set-str INITRAMFS_SOURCE \
            "$rootfs_directory $EFILINUX_INITRAMFS_DEVICES" \
        --set-val INITRAMFS_ROOT_UID "$EFILINUX_INITRAMFS_ROOT_UID" \
        --set-val INITRAMFS_ROOT_GID "$EFILINUX_INITRAMFS_ROOT_GID"
    make -C "$source_directory" O="$EFILINUX_KERNEL_BUILD" olddefconfig

    log "Building EFI-stub kernel with embedded rootfs"
    make -C "$source_directory" O="$EFILINUX_KERNEL_BUILD" \
        -j"$EFILINUX_JOBS" bzImage

    mkdir -p "$EFILINUX_EFI_DIR/EFI/BOOT"
    cp "$EFILINUX_KERNEL_BUILD/arch/x86/boot/bzImage" \
        "$EFILINUX_EFI_DIR/EFI/BOOT/BOOTX64.EFI"
}

case "$mode" in
    modules)
        build_modules
        ;;
    efi)
        build_efi
        ;;
    *)
        die "usage: $0 {modules|efi}"
        ;;
esac
