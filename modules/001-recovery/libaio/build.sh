#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=libaio
pkgver=0.3.113
depends=(glibc)
builddepends=()
makedepends=(gcc make)

prepare() {
    local archive="$downloaddir/libaio-$pkgver.tar.gz"
    download "https://pagure.io/libaio/archive/libaio-$pkgver/libaio-libaio-$pkgver.tar.gz" "$archive"
    checksum sha256 716c7059703247344eb066b54ecbc3ca2134f0103307192e6c2b7dab5f9528ab "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    local compiler
    compiler=$(target_compiler_wrapper gcc)

    make -C "$srcdir/source" \
        -j"$EFILINUX_JOBS" \
        CC="$compiler" \
        CFLAGS="$CFLAGS -Wall -I. -fPIC" \
        LDFLAGS="$LDFLAGS" \
        ENABLE_SHARED=1
    make -C "$srcdir/source" \
        DESTDIR="$develdir" \
        ENABLE_SHARED=1 \
        install
}

devel() {
    rm -f "$develdir/usr/lib/libaio.a"
    strip_all "$develdir/usr/lib"
}

package() {
    local -a keep=()
    package_add_library_family keep 'libaio.so.*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
