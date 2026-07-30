#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=freetype
pkgver=2.14.3

depends=(glibc libpng zlib)
builddepends=()
makedepends=(gcc meson ninja pkg-config python3)

prepare() {
    local archive="$downloaddir/freetype-$pkgver.tar.xz"

    download \
        "https://download.savannah.gnu.org/releases/freetype/freetype-$pkgver.tar.xz" \
        "$archive"
    checksum \
        sha256 \
        36bc4f1cc413335368ee656c42afca65c5a3987e8768cc28cf11ba775e785a5f \
        "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_meson_setup "$srcdir/source" "$builddir" \
        -Dbrotli=disabled \
        -Dbzip2=disabled \
        -Dharfbuzz=disabled \
        -Dmmap=enabled \
        -Dpng=enabled \
        -Dtests=disabled \
        -Dzlib=system
    target_meson_install "$builddir" "$develdir"
}

devel() {
    strip_all "$develdir/usr/lib"
}

package() {
    local -a keep=()
    package_add_library_family keep 'libfreetype.so.6*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
