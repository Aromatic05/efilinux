#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"
pkgname=lzlib
pkgver=1.16
depends=(glibc)
builddepends=()
makedepends=(gcc make)
prepare() {
    local archive="$downloaddir/lzlib-$pkgver.tar.gz"
    download "https://download.savannah.gnu.org/releases/lzip/lzlib/lzlib-$pkgver.tar.gz" "$archive"
    checksum sha256 203228de911780309dad6813e51541d7ea89469784f01cb661edba080ff1b038 "$archive"
    extract "$archive" "$srcdir/source"
}
build() {
    mkdir -p "$builddir"
    (
        cd "$builddir"
        "$srcdir/source/configure" \
            --srcdir="$srcdir/source" \
            --prefix=/usr \
            --libdir=/usr/lib \
            --disable-static \
            --enable-shared \
            --disable-ldconfig \
            CC="$(target_compiler_wrapper gcc)" \
            AR=ar \
            CPPFLAGS="$CPPFLAGS" \
            CFLAGS="$CFLAGS" \
            LDFLAGS="$LDFLAGS"
        make -j"$EFILINUX_JOBS"
        make DESTDIR="$develdir" install
    )
}
devel() { strip_all "$develdir/usr/lib/liblz.so.$pkgver"; }
package() {
    local -a keep=()
    package_add_library_family keep 'liblz.so.1*'
    package_keep "${keep[@]}"
}
recipe_main "$@"
