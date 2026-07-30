#!/usr/bin/env bash

set -euo pipefail

kernel_make() {
    env \
        -u CFLAGS \
        -u CXXFLAGS \
        -u CPPFLAGS \
        -u LDFLAGS \
        MAKEFLAGS= \
        make "$@"
}

set_clean_kernel_config() {
    local scripts_config="$kernel_source_directory/scripts/config"

    "$scripts_config" --file "$kernel_build_directory/.config" \
        --disable CMDLINE_BOOL \
        --set-str CMDLINE "" \
        --set-str INITRAMFS_SOURCE "initramfs.files" \
        --set-val INITRAMFS_ROOT_UID 0 \
        --set-val INITRAMFS_ROOT_GID 0 \
        --disable INITRAMFS_COMPRESSION_GZIP \
        --disable INITRAMFS_COMPRESSION_XZ \
        --enable INITRAMFS_COMPRESSION_ZSTD \
        --disable KERNEL_GZIP \
        --disable KERNEL_XZ \
        --enable KERNEL_ZSTD
    : > "$kernel_build_directory/initramfs.files"
    kernel_make -C "$kernel_source_directory" O="$kernel_build_directory" olddefconfig
    kernel_make -C "$kernel_source_directory" O="$kernel_build_directory" prepare
    python3 "$kernel_config_validator" \
        "$kernel_config_fragment" \
        "$kernel_build_directory/.config"
}

configure_clean_kernel() {
    reset_directory "$kernel_build_directory"

    log "Configuring clean curated common-PC kernel"
    kernel_make -C "$kernel_source_directory" O="$kernel_build_directory" tinyconfig
    "$kernel_source_directory/scripts/kconfig/merge_config.sh" \
        -m \
        -O "$kernel_build_directory" \
        "$kernel_build_directory/.config" \
        "$kernel_config_fragment"
    set_clean_kernel_config
}

ensure_clean_kernel_build_tree() {
    if [[ ! -f "$kernel_build_directory/.config" ]]; then
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
