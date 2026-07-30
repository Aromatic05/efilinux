#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=gmp
pkgver=6.3.0

depends=(glibc)
builddepends=()
makedepends=(gcc make)

prepare() {
    local archive="$downloaddir/gmp-$pkgver.tar.xz"
    download "https://ftp.gnu.org/gnu/gmp/gmp-$pkgver.tar.xz" "$archive"
    checksum sha256 a3c2b80201b89e68616f4ad30bc66aee4927c3ce50e33929ca819d5c43538898 "$archive"
    extract "$archive" "$srcdir/gmp"
}

build() {
    cd "$builddir"
    CC="$CC" CFLAGS="$CFLAGS -std=gnu17" LDFLAGS="$LDFLAGS" \
        "$srcdir/gmp/configure" \
            --prefix=/usr \
            --libdir=/usr/lib \
            --disable-static \
            --enable-shared \
            --enable-cxx=no
    make -j"$EFILINUX_JOBS"
    make DESTDIR="$develdir" install
}

devel() {
    find "$develdir/usr/lib" -maxdepth 1 -name '*.la' -delete
    strip_all "$develdir/usr/lib"
}

package() {
    local target
    target=$(readlink -- "$pkgdir/usr/lib/libgmp.so.10")
    [[ -f "$pkgdir/usr/lib/$target" ]] || die "GMP SONAME target is missing: $target"
    package_keep /usr/lib/libgmp.so.10 "/usr/lib/$target"
}

recipe_main "$@"
