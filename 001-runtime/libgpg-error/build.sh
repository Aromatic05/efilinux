#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=libgpg-error
pkgver=1.61

depends=(glibc)
builddepends=()
makedepends=(gcc make pkg-config)

prepare() {
    local archive="$downloaddir/libgpg-error-$pkgver.tar.bz2"
    download \
        "https://www.gnupg.org/ftp/gcrypt/libgpg-error/libgpg-error-$pkgver.tar.bz2" \
        "$archive"
    checksum sha256 7a85413f2bc354f4f8aa832b718af122e48965e9e0eb9012ee659c13c6385c93 "$archive"
    extract "$archive" "$srcdir/libgpg-error"
}

build() {
    cd "$builddir"
    CC="$CC" CFLAGS="$CFLAGS" CPPFLAGS="$CPPFLAGS" LDFLAGS="$LDFLAGS" \
        "$srcdir/libgpg-error/configure" \
            --prefix=/usr \
            --libdir=/usr/lib \
            --sysconfdir=/etc \
            --disable-static \
            --disable-doc \
            --disable-tests
    make -j"$EFILINUX_JOBS"
    make DESTDIR="$develdir" install
}

devel() {
    find "$develdir/usr/lib" -maxdepth 1 -name '*.la' -delete
    strip_all "$develdir/usr/bin" "$develdir/usr/lib"
}

package() {
    local -a keep=()
    package_add_library_family keep 'libgpg-error.so.0*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
