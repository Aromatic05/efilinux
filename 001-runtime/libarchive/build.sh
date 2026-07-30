#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=libarchive
pkgver=3.8.9

depends=(acl glibc xz zlib zstd)
builddepends=()
makedepends=(gcc make pkg-config)

prepare() {
    local archive="$downloaddir/libarchive-$pkgver.tar.xz"
    download \
        "https://github.com/libarchive/libarchive/releases/download/v$pkgver/libarchive-$pkgver.tar.xz" \
        "$archive"
    checksum sha256 888c934f9d95648ecb9163dc8e23ab80a476ecb81a8f1154704a227b5b676dde "$archive"
    extract "$archive" "$srcdir/libarchive"
}

build() {
    cd "$builddir"
    CC="$CC" CFLAGS="$CFLAGS" CPPFLAGS="$CPPFLAGS" LDFLAGS="$LDFLAGS" \
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
        "$srcdir/libarchive/configure" \
            --prefix=/usr \
            --libdir=/usr/lib \
            --sysconfdir=/etc \
            --disable-static \
            --disable-bsdtar \
            --disable-bsdcpio \
            --disable-bsdcat \
            --without-bz2lib \
            --without-libb2 \
            --without-lz4 \
            --without-nettle \
            --without-openssl \
            --without-xml2 \
            --without-expat
    make -j"$EFILINUX_JOBS"
    make DESTDIR="$develdir" install
}

devel() {
    find "$develdir/usr/lib" -maxdepth 1 -name '*.la' -delete
    strip_all "$develdir/usr/lib"
}

package() {
    local -a keep=()
    package_add_library_family keep 'libarchive.so.13*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
