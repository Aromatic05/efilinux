#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=fmt
pkgver=10.2.1
depends=(glibc)
builddepends=()
makedepends=(cmake gcc g++ ninja)

prepare() {
    local archive="$downloaddir/fmt-$pkgver.tar.gz"
    download "https://github.com/fmtlib/fmt/archive/refs/tags/$pkgver.tar.gz" "$archive"
    checksum sha256 1250e4cc58bf06ee631567523f48848dc4596133e163f02615c97f78bab6c811 "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_cmake_setup "$srcdir/source" "$builddir" \
        -DBUILD_SHARED_LIBS=ON \
        -DFMT_DOC=OFF \
        -DFMT_TEST=OFF
    target_cmake_install "$builddir" "$develdir"
}

devel() {
    strip_all "$develdir/usr/lib"
}

package() {
    local -a keep=()
    package_add_library_family keep 'libfmt.so.10*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
