#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=mpfr
pkgver=4.2.2

depends=(glibc gmp)
builddepends=()
makedepends=(gcc make)

prepare() {
    local archive="$downloaddir/mpfr-$pkgver.tar.xz"
    download "https://ftp.gnu.org/gnu/mpfr/mpfr-$pkgver.tar.xz" "$archive"
    checksum sha256 b67ba0383ef7e8a8563734e2e889ef5ec3c3b898a01d00fa0a6869ad81c6ce01 "$archive"
    extract "$archive" "$srcdir/mpfr"
}

build() {
    cd "$builddir"
    CC="$CC" CFLAGS="$CFLAGS -std=gnu17" LDFLAGS="$LDFLAGS" \
        "$srcdir/mpfr/configure" \
            --prefix=/usr \
            --libdir=/usr/lib \
            --disable-static \
            --enable-shared
    make -j"$EFILINUX_JOBS"
    make DESTDIR="$develdir" install
}

devel() {
    find "$develdir/usr/lib" -maxdepth 1 -name '*.la' -delete
    strip_all "$develdir/usr/lib"
}

package() {
    local target
    target=$(readlink -- "$pkgdir/usr/lib/libmpfr.so.6")
    [[ -f "$pkgdir/usr/lib/$target" ]] || die "MPFR SONAME target is missing: $target"
    package_keep /usr/lib/libmpfr.so.6 "/usr/lib/$target"
}

recipe_main "$@"
