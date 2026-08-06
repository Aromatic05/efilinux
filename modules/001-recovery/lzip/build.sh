#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"
pkgname=lzip
pkgver=1.25
depends=(gcc-libs glibc)
builddepends=()
makedepends=(g++ make)
prepare() {
    local archive="$downloaddir/lzip-$pkgver.tar.gz"
    download "https://download.savannah.gnu.org/releases/lzip/lzip-$pkgver.tar.gz" "$archive"
    checksum sha256 09418a6d8fb83f5113f5bd856e09703df5d37bae0308c668d0f346e3d3f0a56f "$archive"
    extract "$archive" "$srcdir/source"
}
build() {
    mkdir -p "$builddir"
    (
        cd "$builddir"
        "$srcdir/source/configure" \
            --srcdir="$srcdir/source" \
            --prefix=/usr \
            CXX="$(target_compiler_wrapper g++)" \
            CPPFLAGS="$CPPFLAGS" \
            CXXFLAGS="$CXXFLAGS" \
            LDFLAGS="$LDFLAGS"
        make -j"$EFILINUX_JOBS"
        make DESTDIR="$develdir" install
    )
}
devel() { strip_all "$develdir/usr/bin/lzip"; }
package() { package_keep /usr/bin/lzip; }
recipe_main "$@"
