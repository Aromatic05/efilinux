#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=linux
pkgver=6.18.10

depends=()
builddepends=()
makedepends=(bc bison depmod flex gcc make mv openssl perl python3 zstd)

recipe_cache_ready() {
    local recipe_key=$1
    local state="$EFILINUX_BUILD/kernel-state/$recipe_key"

    [[ -d "$state/source" && -d "$state/build" && \
       -f "$state/kernel-common.sh" && -f "$state/common-pc.config" && \
       -f "$state/validate_config.py" ]]
}

prepare() {
    local archive="$downloaddir/linux-$pkgver.tar.xz"

    download \
        "https://www.kernel.org/pub/linux/kernel/v${pkgver%%.*}.x/linux-$pkgver.tar.xz" \
        "$archive"
    checksum \
        md5 \
        660e706a43f634b1fcd911f8839d2f61 \
        "$archive"
    extract "$archive" "$srcdir/linux"
    input_file "$recipedir/common.sh" "$srcdir/kernel-common.sh"
    input_file "$recipedir/common-pc.config" "$srcdir/common-pc.config"
    input_file "$recipedir/validate_config.py" "$srcdir/validate_config.py"
}

build() {
    local kernel_source_directory="$srcdir/linux"
    local kernel_build_directory="$builddir/linux"
    local kernel_config_fragment="$srcdir/common-pc.config"
    local kernel_config_validator="$srcdir/validate_config.py"
    local module_directory="$develdir/usr/lib/modules/$pkgver"
    local state="$EFILINUX_BUILD/kernel-state/$recipe_key"

    source "$srcdir/kernel-common.sh"
    configure_clean_kernel

    log "Building clean kernel image and curated common-PC modules"
    kernel_make -C "$kernel_source_directory" O="$kernel_build_directory" \
        -j"$EFILINUX_JOBS" bzImage modules

    install -Dm0644 \
        "$kernel_build_directory/arch/x86/boot/bzImage" \
        "$develdir/boot/vmlinuz-$pkgver"

    ZSTD_NBTHREADS="${EFILINUX_COMPRESSION_JOBS:-16}" \
    ZSTD="zstd -T${EFILINUX_COMPRESSION_JOBS:-16}" \
        kernel_make -C "$kernel_source_directory" O="$kernel_build_directory" \
            INSTALL_MOD_PATH="$develdir" \
            MODLIB="$module_directory" \
            DEPMOD=true \
            INSTALL_MOD_STRIP=1 \
            modules_install
    rm -f "$module_directory/build" "$module_directory/source"
    find "$module_directory/kernel/net/core" -maxdepth 1 \
        -type f -name 'selftests.ko*' -delete 2>/dev/null || true
    depmod -b "$develdir" -m /usr/lib/modules "$pkgver"

    reset_directory "$state"
    mv "$kernel_source_directory" "$state/source"
    mv "$kernel_build_directory" "$state/build"
    cp "$srcdir/kernel-common.sh" "$state/kernel-common.sh"
    cp "$srcdir/common-pc.config" "$state/common-pc.config"
    cp "$srcdir/validate_config.py" "$state/validate_config.py"
}

package() {
    rm -rf "$pkgdir/boot"
}

recipe_main "$@"
