#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=openjpeg
pkgver=2.5.4

depends=(glibc)
builddepends=()
makedepends=(cmake gcc ninja)

prepare() {
    local archive="$downloaddir/openjpeg-$pkgver.tar.gz"

    download "https://github.com/uclouvain/openjpeg/archive/refs/tags/v$pkgver.tar.gz" "$archive"
    checksum sha256 a695fbe19c0165f295a8531b1e4e855cd94d0875d2f88ec4b61080677e27188a "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_cmake_setup "$srcdir/source" "$builddir" \
        -DBUILD_SHARED_LIBS=ON \
        -DBUILD_STATIC_LIBS=OFF \
        -DBUILD_CODEC=OFF \
        -DBUILD_DOC=OFF \
        -DBUILD_TESTING=OFF \
        -DBUILD_UNIT_TESTS=OFF \
        -DBUILD_LUTS_GENERATOR=OFF \
        -DBUILD_JPIP=OFF \
        -DBUILD_VIEWER=OFF \
        -DBUILD_JAVA=OFF
    target_cmake_install "$builddir" "$develdir"
}

devel() {
    strip_all "$develdir/usr/lib"
}

package() {
    local -a keep=()

    package_add_library_family keep 'libopenjp2.so.7*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
