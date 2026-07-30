#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=upower
pkgver=1.91.3

depends=(glib glibc libgudev polkit)
builddepends=()
makedepends=(gcc meson ninja pkg-config)

prepare() {
    local archive="$downloaddir/upower-$pkgver.tar.gz"
    download \
        "https://gitlab.freedesktop.org/upower/upower/-/archive/v$pkgver/upower-v$pkgver.tar.gz" \
        "$archive"
    checksum sha256 6cef641ce39f13efc09e12afbb889128d4e9b3596a1faeaaa1b619fdf72403a9 "$archive"
    extract "$archive" "$srcdir/upower"
}

build() {
    CC="$CC" \
    CFLAGS="$CFLAGS" \
    LDFLAGS="$LDFLAGS" \
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
        meson setup "$builddir" "$srcdir/upower" \
            --prefix=/usr \
            --libdir=lib \
            --sysconfdir=/etc \
            --localstatedir=/var \
            --buildtype=release \
            --wrap-mode=nodownload \
            -Dman=false \
            -Dgtk-doc=false \
            -Dintrospection=disabled \
            -Didevice=disabled \
            -Dpolkit=enabled \
            -Dinstalled_tests=false \
            -Dudevrulesdir=/usr/lib/udev/rules.d \
            -Dudevhwdbdir=/usr/lib/udev/hwdb.d \
            -Dsystemdsystemunitdir=no
    meson compile -C "$builddir" -j "$EFILINUX_JOBS"
    DESTDIR="$develdir" meson install -C "$builddir"
}

devel() {
    strip_all "$develdir/usr/bin" "$develdir/usr/lib" "$develdir/usr/libexec"
}

package() {
    local -a keep=(
        /etc/UPower/
        /usr/bin/upower
        /usr/libexec/upowerd
        /usr/lib/udev/rules.d/
        /usr/share/dbus-1/
        /usr/share/polkit-1/
    )
    package_add_library_family keep 'libupower-glib.so.3*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
