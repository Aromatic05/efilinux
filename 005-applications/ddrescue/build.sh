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
    checksum sha256 2264622d309d6c87a1cfc19148292b8859a688e9bc02d4702f5cd4f288745542 "$archive"
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
