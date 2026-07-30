#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=libndp
pkgver=1.9

depends=(glibc)
builddepends=(linux-headers)
makedepends=(autoreconf gcc make pkg-config)

prepare() {
    local archive="$downloaddir/libndp-$pkgver.tar.gz"
    download "https://github.com/jpirko/libndp/archive/refs/tags/v$pkgver.tar.gz" "$archive"
    checksum sha256 e564f5914a6b1b799c3afa64c258824a801c1b79a29e2fe6525b682249c65261 "$archive"
    extract "$archive" "$srcdir/libndp"
}

build() {
    autoreconf -fi "$srcdir/libndp"
    cd "$builddir"
    CC="$CC" CFLAGS="$CFLAGS" CPPFLAGS="$CPPFLAGS" LDFLAGS="$LDFLAGS" \
        "$srcdir/libndp/configure" \
            --prefix=/usr \
            --libdir=/usr/lib \
            --sysconfdir=/etc \
            --disable-static
    make -j"$EFILINUX_JOBS"
    make DESTDIR="$develdir" install
}

devel() {
    find "$develdir/usr/lib" -maxdepth 1 -name '*.la' -delete
    strip_all "$develdir/usr/bin" "$develdir/usr/lib"
}

package() {
    local -a keep=()
    package_add_library_family keep 'libndp.so.0*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
