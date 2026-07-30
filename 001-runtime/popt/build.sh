#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=popt
pkgver=1.19

depends=(glibc)
builddepends=()
makedepends=(gcc make)

prepare() {
    local archive="$downloaddir/popt-$pkgver.tar.gz"
    download "https://ftp.osuosl.org/pub/rpm/popt/releases/popt-1.x/popt-$pkgver.tar.gz" "$archive"
    checksum sha256 c25a4838fc8e4c1c8aacb8bd620edb3084a3d63bf8987fdad3ca2758c63240f9 "$archive"
    extract "$archive" "$srcdir/popt"
}

build() {
    cd "$builddir"
    CC="$CC" CFLAGS="$CFLAGS -std=gnu17" LDFLAGS="$LDFLAGS" \
        "$srcdir/popt/configure" \
            --prefix=/usr \
            --libdir=/usr/lib \
            --disable-static \
            --enable-shared \
            --disable-nls
    make -j"$EFILINUX_JOBS"
    make DESTDIR="$develdir" install
}

devel() {
    find "$develdir/usr/lib" -maxdepth 1 -name '*.la' -delete
    strip_all "$develdir/usr/lib"
}

package() {
    local target
    target=$(readlink -- "$pkgdir/usr/lib/libpopt.so.0")
    [[ -f "$pkgdir/usr/lib/$target" ]] || die "popt SONAME target is missing: $target"
    package_keep /usr/lib/libpopt.so.0 "/usr/lib/$target"
}

recipe_main "$@"
