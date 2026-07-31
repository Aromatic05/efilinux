#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
pkgname=hdparm
pkgver=9.65
depends=(glibc)
builddepends=(linux-headers)
makedepends=(gcc make)
prepare() {
    local archive="$downloaddir/hdparm-$pkgver.tar.gz"
    download "https://downloads.sourceforge.net/project/hdparm/hdparm/hdparm-$pkgver.tar.gz" "$archive"
    checksum sha256 d14929f910d060932e717e9382425d47c2e7144235a53713d55a94f7de535a4b "$archive"
    extract "$archive" "$srcdir/source"
}
build() {
    make -C "$srcdir/source" -j"$EFILINUX_JOBS" hdparm \
        CC="$CC" STRIP=: CFLAGS="$CFLAGS -Wall" LDFLAGS="$LDFLAGS"
    install -Dm0755 "$srcdir/source/hdparm" "$develdir/usr/bin/hdparm"
}
devel() { strip_all "$develdir/usr/bin"; }
package() { package_keep /usr/bin/hdparm; }
recipe_main "$@"
