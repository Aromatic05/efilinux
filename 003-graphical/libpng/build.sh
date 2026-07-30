#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=libpng
pkgver=1.6.58

depends=(glibc zlib)
builddepends=()
makedepends=(cmake gcc ninja)

prepare() {
    local archive="$downloaddir/libpng-1.6.58.tar.gz"

    download \
        "https://download.sourceforge.net/libpng/libpng-1.6.58.tar.gz" \
        "$archive"
    checksum \
        sha256 \
        a9d4df463d36a6e5f9c29bd6f4967312d17e996c1854f3511f833924eb1993cf \
        "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_cmake_setup "$srcdir/source" "$builddir" \
        -DPNG_SHARED=ON \
        -DPNG_STATIC=OFF \
        -DPNG_TESTS=OFF \
        -DPNG_TOOLS=OFF \
        -DPNG_EXECUTABLES=OFF
    target_cmake_install "$builddir" "$develdir"
}

devel() {
    find "$develdir/usr/lib" -type f -name '*.la' -delete 2>/dev/null || true
    [[ ! -d "$develdir/usr/bin" ]] || strip_all "$develdir/usr/bin"
    [[ ! -d "$develdir/usr/lib" ]] || strip_all "$develdir/usr/lib"
}

package() {
    local -a keep=()
    package_add_library_family keep 'libpng16.so.16*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
