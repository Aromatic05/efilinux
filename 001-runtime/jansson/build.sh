#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=jansson
pkgver=2.15.1

depends=(glibc)
builddepends=()
makedepends=(gcc make pkg-config)

prepare() {
    local archive="$downloaddir/jansson-$pkgver.tar.gz"
    download \
        "https://github.com/akheron/jansson/releases/download/v$pkgver/jansson-$pkgver.tar.gz" \
        "$archive"
    checksum sha256 0c7114dc0b2d22a670724a1f95922029d7077c19dbf79a584cb8084d2f267f2f "$archive"
    extract "$archive" "$srcdir/jansson"
}

build() {
    cd "$builddir"
    CC="$CC" CFLAGS="$CFLAGS" CPPFLAGS="$CPPFLAGS" LDFLAGS="$LDFLAGS" \
        "$srcdir/jansson/configure" \
            --prefix=/usr \
            --libdir=/usr/lib \
            --sysconfdir=/etc \
            --disable-static
    make -j"$EFILINUX_JOBS"
    make DESTDIR="$develdir" install
}

devel() {
    find "$develdir/usr/lib" -maxdepth 1 -name '*.la' -delete
    strip_all "$develdir/usr/lib"
}

package() {
    local -a keep=()
    package_add_library_family keep 'libjansson.so.4*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
