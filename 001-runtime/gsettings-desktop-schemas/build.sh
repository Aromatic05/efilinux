#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=gsettings-desktop-schemas
pkgver=46.1

depends=(glib)
builddepends=()
makedepends=(glib-compile-schemas meson msgfmt ninja pkg-config)

prepare() {
    local archive="$downloaddir/gsettings-desktop-schemas-$pkgver.tar.xz"
    download \
        "https://download.gnome.org/sources/gsettings-desktop-schemas/${pkgver%.*}/gsettings-desktop-schemas-$pkgver.tar.xz" \
        "$archive"
    checksum sha256 9b88101437a6958ebe6bbd812e49bbf1d09cc667011e415559d847e870468a61 "$archive"
    extract "$archive" "$srcdir/gsettings-desktop-schemas"
}

build() {
    CC="$CC" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
        meson setup "$builddir" "$srcdir/gsettings-desktop-schemas" \
            --prefix=/usr \
            --libdir=lib \
            --sysconfdir=/etc \
            --localstatedir=/var \
            --buildtype=release \
            --wrap-mode=nodownload \
            -Dintrospection=false
    meson compile -C "$builddir" -j "$EFILINUX_JOBS"
    DESTDIR="$develdir" meson install -C "$builddir"
}

devel() {
    rm -f "$develdir/usr/share/glib-2.0/schemas/gschemas.compiled"
}

package() {
    package_keep /usr/share/glib-2.0/schemas/
}

recipe_main "$@"
