#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=libnvme
pkgver=1.16.2

depends=(glibc json-c keyutils openssl)
builddepends=(linux-headers)
makedepends=(gcc meson ninja pkg-config)

prepare() {
    local archive="$downloaddir/libnvme-$pkgver.tar.gz"
    download \
        "https://github.com/linux-nvme/libnvme/archive/refs/tags/v$pkgver.tar.gz" \
        "$archive"
    checksum sha256 1d850d5a871559abf641d6e6b63bb86047e4cb26f3ad144597c2c64b3cff7231 "$archive"
    extract "$archive" "$srcdir/libnvme"
}

build() {
    CC="$CC" \
    CFLAGS="$CFLAGS" \
    LDFLAGS="$LDFLAGS" \
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
        meson setup "$builddir" "$srcdir/libnvme" \
            --prefix=/usr \
            --libdir=lib \
            --libexecdir=lib \
            --sysconfdir=/etc \
            --localstatedir=/var \
            --buildtype=release \
            --wrap-mode=nodownload \
            -Ddocs=false \
            -Ddocs-build=false \
            -Dexamples=false \
            -Dtests=false \
            -Dpython=disabled \
            -Dopenssl=enabled \
            -Dlibdbus=disabled \
            -Djson-c=enabled \
            -Dkeyutils=enabled \
            -Dliburing=disabled
    meson compile -C "$builddir" -j "$EFILINUX_JOBS"
    DESTDIR="$develdir" meson install -C "$builddir"
}

devel() {
    strip_all "$develdir/usr/lib"
}

package() {
    local -a keep=()
    package_add_library_family keep 'libnvme.so.1*'
    package_add_library_family keep 'libnvme-mi.so.1*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
