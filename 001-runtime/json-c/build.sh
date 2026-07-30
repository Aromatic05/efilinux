#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=json-c
pkgver=0.19

depends=(glibc)
builddepends=()
makedepends=(cmake gcc ninja)

prepare() {
    local archive="$downloaddir/json-c-$pkgver.tar.gz"
    download "https://s3.amazonaws.com/json-c_releases/releases/json-c-$pkgver.tar.gz" "$archive"
    checksum sha256 37ad0249902e301bd9052bf712e511fcc6acff4ecaad4b5900aad9ce564e26de "$archive"
    extract "$archive" "$srcdir/json-c"
}

build() {
    cmake -S "$srcdir/json-c" -B "$builddir" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_INSTALL_LIBDIR=lib \
        -DCMAKE_SYSROOT="$EFILINUX_SYSROOT" \
        -DCMAKE_C_FLAGS="$CFLAGS" \
        -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS" \
        -DCMAKE_SHARED_LINKER_FLAGS="$LDFLAGS" \
        -DBUILD_SHARED_LIBS=ON \
        -DBUILD_STATIC_LIBS=OFF \
        -DBUILD_TESTING=OFF \
        -DDISABLE_WERROR=ON
    cmake --build "$builddir" -j "$EFILINUX_JOBS"
    DESTDIR="$develdir" cmake --install "$builddir"
}

devel() {
    strip_all "$develdir/usr/lib"
}

package() {
    local target
    target=$(readlink -- "$pkgdir/usr/lib/libjson-c.so.5")
    [[ -f "$pkgdir/usr/lib/$target" ]] || die "json-c SONAME target is missing: $target"
    package_keep /usr/lib/libjson-c.so.5 "/usr/lib/$target"
}

recipe_main "$@"
