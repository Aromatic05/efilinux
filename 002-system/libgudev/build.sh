#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=libgudev
pkgver=238

depends=(glib udev)
builddepends=()
makedepends=(gcc meson ninja pkg-config)

prepare() {
    local archive="$downloaddir/libgudev-$pkgver.tar.xz"

    download \
        "https://download.gnome.org/sources/libgudev/$pkgver/libgudev-$pkgver.tar.xz" \
        "$archive"
    checksum sha256 61266ab1afc9d73dbc60a8b2af73e99d2fdff47d99544d085760e4fa667b5dd1 "$archive"
    extract "$archive" "$srcdir/libgudev"
}

build() {
    log "Configuring libgudev against the SysVinit udev runtime"
    CC="$CC" \
    CFLAGS="$CFLAGS" \
    LDFLAGS="$LDFLAGS" \
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
        meson setup "$builddir" "$srcdir/libgudev" \
            --prefix=/usr \
            --libdir=lib \
            --buildtype=release \
            --wrap-mode=nodownload \
            -Dtests=disabled \
            -Dintrospection=disabled \
            -Dvapi=disabled \
            -Dgtk_doc=false

    log "Building libgudev"
    meson compile -C "$builddir" -j "$EFILINUX_JOBS"
    DESTDIR="$develdir" meson install -C "$builddir"
}

devel() {
    strip_all "$develdir/usr/lib"
}

package() {
    local -a keep=()
    package_add_library_family keep 'libgudev-1.0.so.0*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
