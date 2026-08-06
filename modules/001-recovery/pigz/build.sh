#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
pkgname=pigz
pkgver=2.8
depends=(glibc zlib)
builddepends=()
makedepends=(gcc make)
prepare() {
    local archive="$downloaddir/pigz-$pkgver.tar.gz"
    download "https://zlib.net/pigz/pigz-$pkgver.tar.gz" "$archive"
    checksum sha256 eb872b4f0e1f0ebe59c9f7bd8c506c4204893ba6a8492de31df416f0d5170fd0 "$archive"
    extract "$archive" "$srcdir/source"
}
build() {
    make -C "$srcdir/source" -j"$EFILINUX_JOBS" CC="$CC" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS"
    install -Dm0755 "$srcdir/source/pigz" "$develdir/usr/bin/pigz"
    ln -s pigz "$develdir/usr/bin/unpigz"
}
devel() { strip_all "$develdir/usr/bin/pigz"; }
package() { package_keep /usr/bin/pigz /usr/bin/unpigz; }
recipe_main "$@"
