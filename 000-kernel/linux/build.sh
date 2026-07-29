#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/000-kernel/linux/common.sh"

require_command bc bison curl depmod flex gcc make md5sum openssl perl python3 strip tar zstd
ensure_directories

producer=${BASH_SOURCE[0]}
kernel_common="$ROOT/000-kernel/linux/common.sh"
kernel_package="linux-$LINUX_VERSION"
kernel_staging="$EFILINUX_BUILD/staging/$kernel_package"
module_directory="/usr/lib/modules/$LINUX_VERSION"
vmlinuz_path="/boot/vmlinuz-$LINUX_VERSION"

recipe_inputs=(
    "$kernel_common"
    "$kernel_config_fragment"
    "$kernel_config_validator"
)

install_modules_tree() {
    local package_root=$1
    local source="$package_root$module_directory"

    [[ -d "$source" ]] || \
        die "kernel package is missing $module_directory"
    replace_rootfs_tree \
        "$kernel_package" "$kernel_package" "$source" "$module_directory"
}

restore_kernel_package() {
    if ! binary_package_extract \
        "$kernel_package" "$kernel_staging" "$producer" \
        "${recipe_inputs[@]}"; then
        return 1
    fi
    [[ -f "$kernel_staging$vmlinuz_path" ]] || \
        die "kernel package is missing $vmlinuz_path"
    [[ -d "$kernel_staging$module_directory" ]] || \
        die "kernel package is missing $module_directory"
    log "Using binary package $(basename -- "$PACKAGE_ARCHIVE")"
    install_modules_tree "$kernel_staging"
    rm -rf -- "$kernel_staging"
}

publish_kernel_package() {
    reset_directory "$kernel_staging"
    mkdir -p \
        "$kernel_staging/boot" \
        "$kernel_staging/usr/lib/modules"
    ln -s usr/lib "$kernel_staging/lib"

    install -m 0644 \
        "$EFILINUX_KERNEL_BUILD/arch/x86/boot/bzImage" \
        "$kernel_staging$vmlinuz_path"

    log "Installing curated common-PC kernel modules"
    ZSTD_NBTHREADS="${EFILINUX_COMPRESSION_JOBS:-16}" \
ZSTD="zstd -T${EFILINUX_COMPRESSION_JOBS:-16}" \
make -C "$kernel_source_directory" O="$EFILINUX_KERNEL_BUILD" \
        INSTALL_MOD_PATH="$kernel_staging" \
        MODLIB="$kernel_staging$module_directory" \
        INSTALL_MOD_STRIP=1 \
        modules_install
    rm -f \
        "$kernel_staging$module_directory/build" \
        "$kernel_staging$module_directory/source"
    depmod -b "$kernel_staging" "$LINUX_VERSION"

    binary_package_create \
        "$kernel_package" "$kernel_staging" "$producer" \
        "${recipe_inputs[@]}"
    install_modules_tree "$kernel_staging"
    rm -rf -- "$kernel_staging"
}

if restore_kernel_package; then
    exit 0
fi

configure_clean_kernel
log "Building clean kernel image and curated common-PC modules"
make -C "$kernel_source_directory" O="$EFILINUX_KERNEL_BUILD" \
    -j"$EFILINUX_JOBS" bzImage modules
publish_kernel_package
