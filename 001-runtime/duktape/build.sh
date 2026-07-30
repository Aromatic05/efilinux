#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=duktape
pkgver=2.7.0

depends=(glibc)
builddepends=()
makedepends=(gcc make)

prepare() {
    local archive="$downloaddir/duktape-$pkgver.tar.xz"
    download "https://duktape.org/duktape-$pkgver.tar.xz" "$archive"
    checksum sha256 90f8d2fa8b5567c6899830ddef2c03f3c27960b11aca222fa17aa7ac613c2890 "$archive"
    extract "$archive" "$srcdir/duktape"
}

build() {
    make -C "$srcdir/duktape" -f Makefile.sharedlibrary \
        CC="$CC" CFLAGS="$CFLAGS -fPIC" LDFLAGS="$LDFLAGS" \
        INSTALL_PREFIX=/usr LIBDIR=/lib
    make -C "$srcdir/duktape" -f Makefile.sharedlibrary install \
        DESTDIR="$develdir" INSTALL_PREFIX=/usr LIBDIR=/lib
}

devel() {
    rm -f "$develdir/usr/lib"/libduktaped.so*
    strip_all "$develdir/usr/lib"
}

package() {
    local -a keep=()
    package_add_library_family keep 'libduktape.so.207*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
