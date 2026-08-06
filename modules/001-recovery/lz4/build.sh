#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
pkgname=lz4
pkgver=1.10.0
depends=(glibc)
builddepends=()
makedepends=(gcc make)
prepare() {
    local archive="$downloaddir/lz4-$pkgver.tar.gz"
    download "https://github.com/lz4/lz4/archive/refs/tags/v$pkgver.tar.gz" "$archive"
    checksum sha256 537512904744b35e232912055ccf8ec66d768639ff3abe5788d90d792ec5f48b "$archive"
    extract "$archive" "$srcdir/source"
}
build() {
    make -C "$srcdir/source/lib" -j"$EFILINUX_JOBS" \
        CC="$CC" CFLAGS="$CFLAGS -fPIC" CPPFLAGS="$CPPFLAGS" \
        LDFLAGS="$LDFLAGS" BUILD_STATIC=no liblz4
    make -C "$srcdir/source/programs" -j"$EFILINUX_JOBS" lz4-release \
        CC="$CC" CFLAGS="$CFLAGS" CPPFLAGS="$CPPFLAGS -I../lib" LDFLAGS="$LDFLAGS"
    install -Dm0644 "$srcdir/source/lib/lz4.h" "$develdir/usr/include/lz4.h"
    install -Dm0644 "$srcdir/source/lib/lz4frame.h" "$develdir/usr/include/lz4frame.h"
    install -Dm0644 "$srcdir/source/lib/lz4hc.h" "$develdir/usr/include/lz4hc.h"
    install -Dm0755 "$srcdir/source/lib/liblz4.so.$pkgver" "$develdir/usr/lib/liblz4.so.$pkgver"
    ln -s "liblz4.so.$pkgver" "$develdir/usr/lib/liblz4.so.1"
    ln -s liblz4.so.1 "$develdir/usr/lib/liblz4.so"
    install -Dm0755 "$srcdir/source/programs/lz4" "$develdir/usr/bin/lz4"
    ln -s lz4 "$develdir/usr/bin/unlz4"
    ln -s lz4 "$develdir/usr/bin/lz4cat"
    install -d -m0755 "$develdir/usr/lib/pkgconfig"
    sed -e 's#@PREFIX@#/usr#g' -e 's#@LIBDIR@#/usr/lib#g' \
        -e 's#@INCLUDEDIR@#/usr/include#g' -e "s#@VERSION@#$pkgver#g" \
        "$srcdir/source/lib/liblz4.pc.in" > "$develdir/usr/lib/pkgconfig/liblz4.pc"
}
devel() { strip_all "$develdir/usr/bin/lz4" "$develdir/usr/lib/liblz4.so.$pkgver"; }
package() {
    local -a keep=(/usr/bin/lz4 /usr/bin/unlz4 /usr/bin/lz4cat)
    package_add_library_family keep 'liblz4.so.1*'
    package_keep "${keep[@]}"
}
recipe_main "$@"
