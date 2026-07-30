#!/usr/bin/env bash

set -euo pipefail

configure_embedded_initramfs() {
    local initramfs_manifest=$1
    local staged_manifest="$kernel_build_directory/initramfs.files"
    local config="$kernel_build_directory/.config"

    [[ -f "$config" ]] || die "kernel link state has no .config"
    grep -Fxq 'CONFIG_INITRAMFS_SOURCE="initramfs.files"' "$config" ||         die "kernel link state does not use the stable initramfs manifest path"
    grep -Fxq 'CONFIG_INITRAMFS_ROOT_UID=0' "$config" ||         die "kernel link state does not preserve initramfs UID metadata"
    grep -Fxq 'CONFIG_INITRAMFS_ROOT_GID=0' "$config" ||         die "kernel link state does not preserve initramfs GID metadata"
    grep -Fxq 'CONFIG_INITRAMFS_COMPRESSION_ZSTD=y' "$config" ||         die "kernel link state does not use zstd initramfs compression"
    grep -Fxq '# CONFIG_INITRAMFS_COMPRESSION_GZIP is not set' "$config" ||         die "kernel link state unexpectedly enables gzip initramfs compression"
    grep -Fxq '# CONFIG_INITRAMFS_COMPRESSION_XZ is not set' "$config" ||         die "kernel link state unexpectedly enables xz initramfs compression"

    install -m0644 "$initramfs_manifest" "$staged_manifest"
}
