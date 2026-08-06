#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"
pkgname=plzip
pkgver=1.12
depends=(gcc-libs glibc lzlib)
builddepends=()
makedepends=(g++ make)
prepare() {
    local archive="$downloaddir/plzip-$pkgver.tar.gz"
    download "https://download.savannah.gnu.org/releases/lzip/plzip/plzip-$pkgver.tar.gz" "$archive"
    checksum sha256 50d71aad6fa154ad8c824279e86eade4bcf3bb4932d757d8f281ac09cfadae30 "$archive"
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
            LDFLAGS="$LDFLAGS" \
            LIBS='-llz -lpthread'
        make -j"$EFILINUX_JOBS"
        make DESTDIR="$develdir" install
    )
}
devel() { strip_all "$develdir/usr/bin/plzip"; }
package() { package_keep /usr/bin/plzip; }
recipe_main "$@"
