#!/usr/bin/env bash

set -euo pipefail

kernel_archive="$EFILINUX_DOWNLOADS/linux-$LINUX_VERSION.tar.xz"
kernel_source_directory="$EFILINUX_BUILD/sources/linux-$LINUX_VERSION-kernel"
kernel_config_fragment="$ROOT/000-kernel/linux/common-pc.config"
kernel_config_validator="$ROOT/000-kernel/linux/validate_config.py"

ensure_kernel_source() {
    download \
        "https://www.kernel.org/pub/linux/kernel/v${LINUX_VERSION%%.*}.x/linux-$LINUX_VERSION.tar.xz" \
        "$kernel_archive"
    verify_md5 "$LINUX_MD5" "$kernel_archive"
    if [[ ! -f "$kernel_source_directory/Makefile" ]]; then
        extract_source "$kernel_archive" "$kernel_source_directory"
    fi
}

set_clean_kernel_config() {
    local scripts_config="$kernel_source_directory/scripts/config"

    "$scripts_config" --file "$EFILINUX_KERNEL_BUILD/.config" \
        --disable CMDLINE_BOOL \
        --set-str CMDLINE "" \
        --set-str INITRAMFS_SOURCE "" \
        --disable KERNEL_GZIP \
        --disable KERNEL_XZ \
        --enable KERNEL_ZSTD
    make -C "$kernel_source_directory" O="$EFILINUX_KERNEL_BUILD" olddefconfig
    make -C "$kernel_source_directory" O="$EFILINUX_KERNEL_BUILD" prepare
    python3 "$kernel_config_validator" \
        "$kernel_config_fragment" \
        "$EFILINUX_KERNEL_BUILD/.config"
}

configure_clean_kernel() {
    ensure_kernel_source
    reset_directory "$EFILINUX_KERNEL_BUILD"

    log "Configuring clean curated common-PC kernel"
    make -C "$kernel_source_directory" O="$EFILINUX_KERNEL_BUILD" tinyconfig
    "$kernel_source_directory/scripts/kconfig/merge_config.sh" \
        -m \
        -O "$EFILINUX_KERNEL_BUILD" \
        "$EFILINUX_KERNEL_BUILD/.config" \
        "$kernel_config_fragment"
    set_clean_kernel_config
}

ensure_clean_kernel_build_tree() {
    ensure_kernel_source
    if [[ ! -f "$EFILINUX_KERNEL_BUILD/.config" ]]; then
        configure_clean_kernel
        return
    fi
    set_clean_kernel_config
}

remove_embedded_initramfs_outputs() {
    local build_root=$1

    rm -f \
        "$build_root/vmlinux" \
        "$build_root/vmlinux.o" \
        "$build_root/System.map" \
        "$build_root/arch/x86/boot/bzImage" \
        "$build_root/usr/built-in.a" \
        "$build_root/usr/.built-in.a.cmd" \
        "$build_root/usr/initramfs_data.cpio" \
        "$build_root/usr/initramfs_data.cpio.gz" \
        "$build_root/usr/initramfs_data.cpio.xz" \
        "$build_root/usr/initramfs_data.cpio.zst" \
        "$build_root/usr/initramfs_data.o" \
        "$build_root/usr/initramfs_inc_data" \
        "$build_root/usr/.initramfs_data.cpio.cmd" \
        "$build_root/usr/.initramfs_data.cpio.d" \
        "$build_root/usr/.initramfs_data.o.cmd" \
        "$build_root/usr/.initramfs_inc_data.cmd"
    find "$build_root" -maxdepth 1 -type f \
        \( -name '.vmlinux*' -o -name 'vmlinux.*' \) \
        ! -name 'vmlinux.a' -delete
}

configure_embedded_initramfs() {
    local initramfs_tree=$1
    local device_manifest=$2
    local scripts_config="$kernel_source_directory/scripts/config"

    "$scripts_config" --file "$EFILINUX_KERNEL_BUILD/.config" \
        --set-str INITRAMFS_SOURCE "$initramfs_tree $device_manifest" \
        --set-val INITRAMFS_ROOT_UID "$EFILINUX_INITRAMFS_ROOT_UID" \
        --set-val INITRAMFS_ROOT_GID "$EFILINUX_INITRAMFS_ROOT_GID" \
        --disable INITRAMFS_COMPRESSION_GZIP \
        --disable INITRAMFS_COMPRESSION_XZ \
        --enable INITRAMFS_COMPRESSION_ZSTD
    make -C "$kernel_source_directory" O="$EFILINUX_KERNEL_BUILD" olddefconfig
    python3 "$kernel_config_validator" \
        "$kernel_config_fragment" \
        "$EFILINUX_KERNEL_BUILD/.config"
}
