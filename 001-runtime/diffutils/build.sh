#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
pkgname=diffutils
pkgver=3.12
depends=(glibc)
builddepends=()
makedepends=(gcc make)
prepare() {
    local archive="$downloaddir/diffutils-$pkgver.tar.xz"
    download "https://ftp.gnu.org/gnu/diffutils/diffutils-$pkgver.tar.xz" "$archive"
    checksum sha256 7c8b7f9fc8609141fdea9cece85249d308624391ff61dedaf528fcb337727dfd "$archive"
    extract "$archive" "$srcdir/source"
}
build() {
    local small_cflags="${CFLAGS/-O2/-Os} -ffunction-sections -fdata-sections"
    local small_ldflags="$LDFLAGS -Wl,--gc-sections"
    cd "$builddir"
    target_env env CFLAGS="$small_cflags" LDFLAGS="$small_ldflags" \
        "$srcdir/source/configure" --prefix=/usr --bindir=/usr/bin \
        --disable-nls --disable-dependency-tracking
    make -j"$EFILINUX_JOBS"
    make DESTDIR="$develdir" install
}
devel() { rm -rf "$develdir/usr/share"; strip_all "$develdir/usr/bin"; }
package() { package_keep /usr/bin/cmp /usr/bin/diff /usr/bin/diff3 /usr/bin/sdiff; }
recipe_main "$@"
