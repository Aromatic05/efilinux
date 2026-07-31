#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
pkgname=efibootmgr
pkgver=18
depends=(efivar glibc popt)
builddepends=()
makedepends=(gcc make pkg-config)
prepare() {
    local archive="$downloaddir/efibootmgr-$pkgver.tar.gz"
    download "https://github.com/rhboot/efibootmgr/archive/refs/tags/$pkgver.tar.gz" "$archive"
    checksum sha256 442867d12f8525034a404fc8af3036dba8e1fc970998af2486c3b940dfad0874 "$archive"
    extract "$archive" "$srcdir/source"
}
build() {
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
    make -C "$srcdir/source" -j"$EFILINUX_JOBS" \
        EFIDIR=BOOT prefix=/usr libdir=/usr/lib sbindir=/usr/bin \
        CC="$CC" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS"
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
    make -C "$srcdir/source" install \
        EFIDIR=BOOT prefix=/usr libdir=/usr/lib sbindir=/usr/bin \
        DESTDIR="$develdir" CC="$CC" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS"
}
devel() { strip_all "$develdir/usr/bin"; }
package() { package_keep /usr/bin/efibootmgr /usr/bin/efibootdump; }
recipe_main "$@"
