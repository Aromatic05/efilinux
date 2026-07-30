#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=libjpeg-turbo
pkgver=3.2.0

depends=(glibc)
builddepends=()
makedepends=(cmake gcc nasm ninja)

prepare() {
    local archive="$downloaddir/libjpeg-turbo-3.2.0.tar.gz"

    download \
        "https://github.com/libjpeg-turbo/libjpeg-turbo/releases/download/3.2.0/libjpeg-turbo-3.2.0.tar.gz" \
        "$archive"
    checksum \
        sha256 \
        6f30092cef9fb839779646608f4ee14ae3cbac989c47fa05e841b0841f09878e \
        "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_cmake_setup "$srcdir/source" "$builddir" \
        -DENABLE_SHARED=ON \
        -DENABLE_STATIC=OFF \
        -DWITH_SIMD=ON \
        -DWITH_TURBOJPEG=OFF \
        -DWITH_TOOLS=OFF \
        -DWITH_TESTS=OFF \
        -DWITH_FUZZ=OFF
    target_cmake_install "$builddir" "$develdir"
}

devel() {
    find "$develdir/usr/lib" -type f -name '*.la' -delete 2>/dev/null || true
    [[ ! -d "$develdir/usr/bin" ]] || strip_all "$develdir/usr/bin"
    [[ ! -d "$develdir/usr/lib" ]] || strip_all "$develdir/usr/lib"
}

package() {
    local -a keep=()
    package_add_library_family keep 'libjpeg.so.62*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
