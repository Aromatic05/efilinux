#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=pulseaudio
pkgver=17.0

depends=(dbus glib glibc libsndfile)
builddepends=()
makedepends=(gcc meson ninja pkg-config)

prepare() {
    local archive="$downloaddir/pulseaudio-$pkgver.tar.xz"
    download \
        "https://freedesktop.org/software/pulseaudio/releases/pulseaudio-$pkgver.tar.xz" \
        "$archive"
    checksum sha256 053794d6671a3e397d849e478a80b82a63cb9d8ca296bd35b73317bb5ceb87b5 "$archive"
    extract "$archive" "$srcdir/pulseaudio"
}

build() {
    CC="$CC" \
    CFLAGS="$CFLAGS" \
    LDFLAGS="$LDFLAGS" \
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
        meson setup "$builddir" "$srcdir/pulseaudio" \
            --prefix=/usr \
            --libdir=lib \
            --libexecdir=lib \
            --sysconfdir=/etc \
            --localstatedir=/var \
            --buildtype=release \
            --wrap-mode=nodownload \
            --auto-features=disabled \
            -Ddaemon=false \
            -Dclient=true \
            -Ddoxygen=false \
            -Dman=false \
            -Dtests=false \
            -Ddatabase=simple \
            -Dalsa=disabled \
            -Dasyncns=disabled \
            -Davahi=disabled \
            -Dbluez5=disabled \
            -Dconsolekit=disabled \
            -Ddbus=enabled \
            -Delogind=disabled \
            -Dfftw=disabled \
            -Dglib=enabled \
            -Dgsettings=disabled \
            -Dgstreamer=disabled \
            -Dgtk=disabled \
            -Djack=disabled \
            -Dlirc=disabled \
            -Dopenssl=disabled \
            -Dorc=disabled \
            -Doss-output=disabled \
            -Dsamplerate=disabled \
            -Dsoxr=disabled \
            -Dspeex=disabled \
            -Dsystemd=disabled \
            -Dtcpwrap=disabled \
            -Dudev=disabled \
            -Dx11=disabled
    meson compile -C "$builddir" -j "$EFILINUX_JOBS"
    DESTDIR="$develdir" meson install -C "$builddir"
}

devel() {
    strip_all "$develdir/usr/bin" "$develdir/usr/lib"
}

package() {
    local -a keep=(
        /usr/bin/pactl
        /usr/bin/pacat
        /usr/lib/pulseaudio/
    )
    package_add_library_family keep 'libpulse.so.0*'
    package_add_library_family keep 'libpulse-mainloop-glib.so.0*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
