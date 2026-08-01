#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=boost
pkgver=1.89.0
depends=(glibc zlib)
builddepends=()
makedepends=(cmake gcc g++ ninja)

prepare() {
    local archive="$downloaddir/boost-$pkgver.tar.gz"
    download "https://github.com/boostorg/boost/releases/download/boost-$pkgver/boost-$pkgver-cmake.tar.gz" "$archive"
    checksum sha256 954a01219bf818c7fb850fa610c2c8c71a4fa28fa32a1900056bcb6ff58cf908 "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_cmake_setup "$srcdir/source" "$builddir" \
        -DBOOST_INCLUDE_LIBRARIES=iostreams \
        -DBUILD_SHARED_LIBS=ON \
        -DBUILD_TESTING=OFF
    target_cmake_install "$builddir" "$develdir"
    while IFS= read -r include_directory; do
        cp -a "$include_directory/." "$develdir/usr/include/boost/"
    done < <(find "$srcdir/source/libs" -type d -path '*/include/boost' | LC_ALL=C sort)
}

devel() {
    strip_all "$develdir/usr/lib"
}

package() {
    local -a keep=()
    package_add_library_family keep 'libboost_iostreams.so.1.89.0'
    package_keep "${keep[@]}"
}

recipe_main "$@"
