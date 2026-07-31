#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
pkgname=gawk
pkgver=5.4.1
depends=(glibc)
builddepends=()
makedepends=(gcc make)
prepare() {
    local archive="$downloaddir/gawk-$pkgver.tar.xz"
    download "https://ftp.gnu.org/gnu/gawk/gawk-$pkgver.tar.xz" "$archive"
    checksum sha256 07f6f7342b7febe4313fc2c2542ad93d64fe20ad8717200109f105a826f5fd37 "$archive"
    extract "$archive" "$srcdir/source"
    [[ "$RECIPE_INPUT_MODE" == metadata ]] && return
    sed -i 's/extras//' "$srcdir/source/Makefile.in"
}
build() {
    local small_cflags="${CFLAGS/-O2/-Os} -ffunction-sections -fdata-sections"
    local small_ldflags="$LDFLAGS -Wl,--gc-sections"
    cd "$builddir"
    target_env env CFLAGS="$small_cflags" LDFLAGS="$small_ldflags" \
        "$srcdir/source/configure" --prefix=/usr --bindir=/usr/bin \
        --disable-nls --disable-dependency-tracking --disable-lint \
        --disable-mpfr --disable-extensions --without-readline
    make -j"$EFILINUX_JOBS"
    make DESTDIR="$develdir" install
}
devel() {
    rm -rf "$develdir/usr/share" "$develdir/usr/lib/gawk"
    rm -f "$develdir/usr/bin/gawk-$pkgver"
    ln -sf gawk "$develdir/usr/bin/awk"
    strip_all "$develdir/usr/bin/gawk"
}
package() { package_keep /usr/bin/gawk /usr/bin/awk; }
recipe_main "$@"
