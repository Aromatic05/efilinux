#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=libnl
pkgver=3.12.0

depends=(glibc)
builddepends=(linux-headers)
makedepends=(autoreconf gcc make pkg-config)

prepare() {
    local archive="$downloaddir/libnl-$pkgver.tar.gz"
    download \
        "https://github.com/thom311/libnl/archive/refs/tags/libnl${pkgver//./_}.tar.gz" \
        "$archive"
    checksum sha256 a0dee52ff800a74cffbd02d64950ab7149a1df642dbdb4d601f66727b14ad021 "$archive"
    extract "$archive" "$srcdir/libnl"
}

build() {
    autoreconf -fi "$srcdir/libnl"
    cd "$builddir"
    CC="$CC" CFLAGS="$CFLAGS" CPPFLAGS="$CPPFLAGS" LDFLAGS="$LDFLAGS" \
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
        "$srcdir/libnl/configure" \
            --prefix=/usr \
            --libdir=/usr/lib \
            --sysconfdir=/etc \
            --disable-static
    make -j"$EFILINUX_JOBS"
    make DESTDIR="$develdir" install
}

devel() {
    find "$develdir/usr/lib" -maxdepth 1 -name '*.la' -delete
    strip_all "$develdir/usr/bin" "$develdir/usr/lib"
}

package() {
    local -a keep=()
    package_add_library_family keep 'libnl-3.so.200*'
    package_add_library_family keep 'libnl-genl-3.so.200*'
    package_add_library_family keep 'libnl-route-3.so.200*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
