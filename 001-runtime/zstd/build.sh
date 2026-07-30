#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=zstd
pkgver=1.5.7

depends=(
    glibc
)
builddepends=()
makedepends=(
    gcc
    make
)

prepare() {
    local archive="$downloaddir/zstd-$pkgver.tar.gz"

    download \
        "https://github.com/facebook/zstd/releases/download/v$pkgver/zstd-$pkgver.tar.gz" \
        "$archive"
    checksum \
        md5 \
        780fc1896922b1bc52a4e90980cdda48 \
        "$archive"
    extract "$archive" "$srcdir/zstd"
}

build() {
    log "Building Zstandard"
    CC="$CC" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
        make -C "$srcdir/zstd" -j"$EFILINUX_JOBS" \
            ZSTD_LEGACY_SUPPORT=0 \
            ZSTD_BUILD_STATIC=0

    CC="$CC" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
        make -C "$srcdir/zstd" \
            prefix=/usr \
            libdir=/usr/lib \
            DESTDIR="$develdir" \
            ZSTD_LEGACY_SUPPORT=0 \
            ZSTD_BUILD_STATIC=0 \
            install

    rm -f "$develdir/usr/lib/libzstd.a"
}

devel() {
    strip_all \
        "$develdir/usr/bin" \
        "$develdir/usr/lib"
}

package() {
    local libzstd_target

    libzstd_target=$(readlink -- "$pkgdir/usr/lib/libzstd.so.1")
    [[ -f "$pkgdir/usr/lib/$libzstd_target" ]] || \
        die "Zstandard runtime SONAME target is missing: $libzstd_target"

    package_keep \
        /usr/bin/zstd \
        /usr/bin/unzstd \
        /usr/bin/zstdcat \
        /usr/lib/libzstd.so.1 \
        "/usr/lib/$libzstd_target"
}

recipe_main "$@"
