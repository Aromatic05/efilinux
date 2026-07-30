#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=lsof
pkgver=4.99.5
depends=(glibc)
builddepends=(linux-headers)
makedepends=(gcc make)

prepare() {
    local archive="$downloaddir/lsof-$pkgver.tar.gz"
    download "https://github.com/lsof-org/lsof/releases/download/$pkgver/lsof-$pkgver.tar.gz" "$archive"
    checksum sha256 12a3f1d974d90bb2e5657c8faf5ba1a1f3790db27333166aa52b61c0f8d5c9c0 "$archive"
    extract "$archive" "$srcdir/lsof"
}

build() {
    cd "$builddir"
    target_env "$srcdir/lsof/configure" --prefix=/usr --disable-static
    make -j"$EFILINUX_JOBS"
    make DESTDIR="$develdir" install
}

devel() { strip_all "$develdir/usr/bin"; }
package() { package_keep /usr/bin/lsof; }

recipe_main "$@"
