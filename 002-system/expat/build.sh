#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=expat
pkgver=2.8.2

depends=(glibc)
builddepends=()
makedepends=(gcc make)

prepare() {
    local archive="$downloaddir/expat-$pkgver.tar.xz"
    download \
        "https://github.com/libexpat/libexpat/releases/download/R_${pkgver//./_}/expat-$pkgver.tar.xz" \
        "$archive"
    checksum sha256 3ad89b8588e6644bd4e49981480d48b21289eebbcd4f0a1a4afb1c29f99b6ab4 "$archive"
    extract "$archive" "$srcdir/expat"
}

build() {
    cd "$builddir"
    CC="$CC" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
        "$srcdir/expat/configure" \
            --prefix=/usr \
            --libdir=/usr/lib \
            --disable-static \
            --without-docbook \
            --without-xmlwf
    make -j"$EFILINUX_JOBS"
    make DESTDIR="$develdir" install
}

devel() {
    find "$develdir/usr/lib" -maxdepth 1 -name '*.la' -delete 2>/dev/null || true
    strip_all "$develdir/usr/lib"
}

package() {
    local -a keep=()
    package_add_library_family keep 'libexpat.so.1*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
