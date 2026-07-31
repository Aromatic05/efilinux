#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=wireplumber
pkgver=0.5.15

depends=(elogind glib lua pipewire)
builddepends=()
makedepends=(gcc meson ninja pkg-config)

prepare() {
    local archive="$downloaddir/wireplumber-$pkgver.tar.gz"
    download \
        "https://gitlab.freedesktop.org/pipewire/wireplumber/-/archive/$pkgver/wireplumber-$pkgver.tar.gz" \
        "$archive"
    checksum sha256 baa121bc918df5fa0e0e70755bb1c99ffab0ab107225ecf99aa470e2c6ba5e7b "$archive"
    extract "$archive" "$srcdir/wireplumber"
}

build() {
    mkdir -p "$builddir/pkgconfig"
    cp "$EFILINUX_SYSROOT/usr/lib/pkgconfig/lua.pc" "$builddir/pkgconfig/lua-5.4.pc"
    cp "$EFILINUX_SYSROOT/usr/lib/pkgconfig/lua.pc" "$builddir/pkgconfig/lua5.4.pc"

    CC="$CC" \
    CFLAGS="$CFLAGS" \
    LDFLAGS="$LDFLAGS" \
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$builddir/pkgconfig:$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
        meson setup "$builddir/build" "$srcdir/wireplumber" \
            --prefix=/usr \
            --libdir=lib \
            --libexecdir=lib \
            --sysconfdir=/etc \
            --localstatedir=/var \
            --buildtype=release \
            --wrap-mode=nodownload \
            --auto-features=disabled \
            -Dintrospection=disabled \
            -Ddoc=disabled \
            -Dmodules=true \
            -Ddaemon=true \
            -Dtools=true \
            -Dsystem-lua=true \
            -Dsystem-lua-version=5.4 \
            -Delogind=enabled \
            -Dsystemd=disabled \
            -Dsystemd-system-service=false \
            -Dsystemd-user-service=false \
            -Dtests=false \
            -Ddbus-tests=false
    meson compile -C "$builddir/build" -j "$EFILINUX_JOBS"
    DESTDIR="$develdir" meson install -C "$builddir/build"
}

devel() {
    rm -f "$develdir/usr/share/wireplumber/scripts/linking/find-user-target.lua.example"
    strip_all "$develdir/usr/bin" "$develdir/usr/lib"
}

package() {
    local -a keep=(
        /usr/bin/wireplumber
        /usr/bin/wpctl
        /usr/lib/wireplumber-0.5/
        /usr/share/wireplumber/
    )
    package_add_library_family keep 'libwireplumber-0.5.so.0*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
