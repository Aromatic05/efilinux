#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=xz
pkgver=5.8.2

depends=(
    glibc
)
builddepends=()
makedepends=(
    gcc
    make
)

prepare() {
    local archive="$downloaddir/xz-$pkgver.tar.xz"

    download \
        "https://github.com/tukaani-project/xz/releases/download/v$pkgver/xz-$pkgver.tar.xz" \
        "$archive"
    checksum \
        md5 \
        87c8bb8addf7189d3a51f6a5f03163fc \
        "$archive"
    extract "$archive" "$srcdir/xz"
}

build() {
    log "Configuring XZ Utils"
    cd "$builddir"
    CC="$CC" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
        "$srcdir/xz/configure" \
            --prefix=/usr \
            --libdir=/usr/lib \
            --disable-static \
            --disable-doc \
            --disable-nls

    log "Building XZ Utils"
    make -j"$EFILINUX_JOBS"
    make DESTDIR="$develdir" install
}

devel() {
    strip_all \
        "$develdir/usr/bin" \
        "$develdir/usr/lib"
}

package() {
    local liblzma_target

    liblzma_target=$(readlink -- "$pkgdir/usr/lib/liblzma.so.5")
    [[ -f "$pkgdir/usr/lib/$liblzma_target" ]] || \
        die "XZ runtime SONAME target is missing: $liblzma_target"

    package_keep \
        /usr/bin/xz \
        /usr/bin/unxz \
        /usr/bin/xzcat \
        /usr/lib/liblzma.so.5 \
        "/usr/lib/$liblzma_target"
}

recipe_main "$@"
