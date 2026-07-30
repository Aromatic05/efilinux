#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=pipewire
pkgver=1.6.8

depends=(alsa-lib dbus glib glibc ncurses readline udev)
builddepends=()
makedepends=(gcc meson ninja pkg-config)

prepare() {
    local archive="$downloaddir/pipewire-$pkgver.tar.gz"
    download \
        "https://gitlab.freedesktop.org/pipewire/pipewire/-/archive/$pkgver/pipewire-$pkgver.tar.gz" \
        "$archive"
    checksum sha256 8181172a1d95131f6af8bbc0b98f90b2a33349b042b84c3ce57dd5d11348cc58 "$archive"
    extract "$archive" "$srcdir/pipewire"
}

build() {
    CC="$CC" \
    CFLAGS="$CFLAGS" \
    LDFLAGS="$LDFLAGS" \
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
        meson setup "$builddir" "$srcdir/pipewire" \
            --prefix=/usr \
            --libdir=lib \
            --libexecdir=lib \
            --sysconfdir=/etc \
            --localstatedir=/var \
            --buildtype=release \
            --wrap-mode=nodownload \
            --auto-features=disabled \
            -Ddocs=disabled \
            -Dman=disabled \
            -Dexamples=disabled \
            -Dtests=disabled \
            -Dsystemd-system-service=disabled \
            -Dsystemd-user-service=disabled \
            -Dselinux=disabled \
            -Dpipewire-alsa=enabled \
            -Dpipewire-jack=disabled \
            -Dalsa=enabled \
            -Dbluez5=disabled \
            -Djack=disabled \
            -Dv4l2=disabled \
            -Ddbus=enabled \
            -Dlibcamera=disabled \
            -Dudev=enabled \
            -Dudevrulesdir=/usr/lib/udev/rules.d \
            -Dsndfile=disabled \
            -Davahi=disabled \
            -Dsession-managers=[] \
            -Dx11=disabled \
            -Dreadline=enabled \
            -Dgsettings=disabled \
            -Dfftw=disabled \
            -Dgstreamer=disabled
    meson compile -C "$builddir" -j "$EFILINUX_JOBS"
    DESTDIR="$develdir" meson install -C "$builddir"
}

devel() {
    strip_all "$develdir/usr/bin" "$develdir/usr/lib"
}

package() {
    local -a keep=(
        /usr/bin/pipewire
        /usr/bin/pipewire-pulse
        /usr/bin/pw-cli
        /usr/bin/pw-dump
        /usr/bin/pw-link
        /usr/bin/pw-metadata
        /usr/lib/pipewire-0.3/
        /usr/lib/spa-0.2/
        /usr/share/pipewire/
        /usr/share/alsa/alsa.conf.d/
        /usr/lib/udev/rules.d/
    )
    package_add_library_family keep 'libpipewire-0.3.so.0*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
