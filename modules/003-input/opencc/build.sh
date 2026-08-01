#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=opencc
pkgver=1.1.9
depends=(glibc)
builddepends=()
makedepends=(cmake gcc g++ ninja)

prepare() {
    local archive="$downloaddir/opencc-$pkgver.tar.gz"
    download "https://github.com/BYVoid/OpenCC/archive/refs/tags/ver.$pkgver.tar.gz" "$archive"
    checksum sha256 ad4bcd8d87219a240a236d4a55c9decd2132a9436697d2882ead85c8939b0a99 "$archive"
    extract "$archive" "$srcdir/source"
    input_file "$recipedir/files/gcc16-cstdint.patch" "$srcdir/gcc16-cstdint.patch"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
    [[ "$RECIPE_INPUT_MODE" == metadata ]] && return
    patch -d "$srcdir/source" -p1 < "$srcdir/gcc16-cstdint.patch"
}

build() {
    target_cmake_setup "$srcdir/source" "$builddir" \
        -DBUILD_DOCUMENTATION=OFF \
        -DENABLE_GTEST=OFF \
        -DENABLE_BENCHMARK=OFF \
        -DBUILD_PYTHON=OFF \
        -DBUILD_SHARED_LIBS=ON
    target_cmake_install "$builddir" "$develdir"
}

devel() {
    strip_all "$develdir/usr/bin" "$develdir/usr/lib"
}

package() {
    local -a keep=(/usr/share/opencc/)
    package_add_library_family keep 'libopencc.so.1*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
