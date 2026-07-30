#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=ddrescue
pkgver=1.30
depends=(glibc)
builddepends=()
makedepends=(gcc make)

prepare() {
    local archive="$downloaddir/ddrescue-$pkgver.tar.lz"
    download "https://download.savannah.gnu.org/releases/ddrescue/ddrescue-$pkgver.tar.lz" "$archive"
    checksum sha256 7cbd5b59ee4fc3b029b8e7800c77f38dbfbdac7a64d0d73e0e43ba9fc3c46421 "$archive"
    extract "$archive" "$srcdir/ddrescue"
}

build() {
    cd "$builddir"
    target_env "$srcdir/ddrescue/configure" --prefix=/usr
    make -j"$EFILINUX_JOBS"
    make DESTDIR="$develdir" install
}

devel() { strip_all "$develdir/usr/bin"; }
package() { package_keep /usr/bin/ddrescue; }

recipe_main "$@"
