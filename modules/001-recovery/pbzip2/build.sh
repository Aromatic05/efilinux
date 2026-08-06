#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
pkgname=pbzip2
pkgver=1.1.13
depends=(bzip2 gcc-libs glibc)
builddepends=()
makedepends=(g++ make)
prepare() {
    local archive="$downloaddir/pbzip2-$pkgver.tar.gz"
    download "https://launchpad.net/pbzip2/1.1/$pkgver/+download/pbzip2-$pkgver.tar.gz" "$archive"
    checksum sha256 8fd13eaaa266f7ee91f85c1ea97c86d9c9cc985969db9059cdebcb1e1b7bdbe6 "$archive"
    extract "$archive" "$srcdir/source"
}
build() {
    make -C "$srcdir/source" -j"$EFILINUX_JOBS" \
        CXX="$CXX" CXXFLAGS="$CXXFLAGS" LDFLAGS="$LDFLAGS" pbzip2
    install -Dm0755 "$srcdir/source/pbzip2" "$develdir/usr/bin/pbzip2"
}
devel() { strip_all "$develdir/usr/bin/pbzip2"; }
package() { package_keep /usr/bin/pbzip2; }
recipe_main "$@"
