#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=bc
pkgver=1.08.2
depends=(glibc readline)
builddepends=()
makedepends=(gcc make)

prepare() {
    local archive="$downloaddir/bc-$pkgver.tar.gz"
    download "https://ftp.gnu.org/gnu/bc/bc-$pkgver.tar.gz" "$archive"
    checksum sha256 ae470fec429775653e042015edc928d07c8c3b2fc59765172a330d3d87785f86 "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_release_configure "$srcdir/source" "$builddir" \
        --bindir=/usr/bin \
        --with-readline \
        --disable-dc-bang-shell
    target_make_install "$builddir" "$develdir"
}

devel() {
    strip_all "$develdir/usr/bin"
}

package() {
    package_keep /usr/bin/bc /usr/bin/dc
}

recipe_main "$@"
