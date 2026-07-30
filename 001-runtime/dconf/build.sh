#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=dconf
pkgver=0.40.0

depends=(dbus glib glibc)
builddepends=()
makedepends=(gcc meson ninja patch pkg-config)

prepare() {
    local archive="$downloaddir/dconf-$pkgver.tar.xz"
    download \
        "https://download.gnome.org/sources/dconf/${pkgver%.*}/dconf-$pkgver.tar.xz" \
        "$archive"
    checksum sha256 cf7f22a4c9200421d8d3325c5c1b8b93a36843650c9f95d6451e20f0bcb24533 "$archive"
    extract "$archive" "$srcdir/dconf"
    input_file "$recipedir/patches/0001-use-target-runtime-directories.patch" \
        "$srcdir/use-target-runtime-directories.patch"
}

build() {
    patch -d "$srcdir/dconf" -Np1 < "$srcdir/use-target-runtime-directories.patch"
    CC="$CC" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
        meson setup "$builddir" "$srcdir/dconf" \
            --prefix=/usr \
            --libdir=lib \
            --sysconfdir=/etc \
            --localstatedir=/var \
            --buildtype=release \
            --wrap-mode=nodownload \
            -Dbash_completion=false \
            -Dman=false \
            -Dgtk_doc=false \
            -Dvapi=false \
            -Dsystemduserunitdir=''
    meson compile -C "$builddir" -j "$EFILINUX_JOBS"
    DESTDIR="$develdir" meson install -C "$builddir"
    sed -i '/^SystemdService=/d' \
        "$develdir/usr/share/dbus-1/services/ca.desrt.dconf.service"
}

devel() {
    strip_all "$develdir/usr/bin" "$develdir/usr/lib" "$develdir/usr/libexec"
}

package() {
    local -a keep=(
        /usr/bin/dconf
        /usr/lib/gio/modules/libdconfsettings.so
        /usr/libexec/dconf-service
        /usr/share/dbus-1/services/ca.desrt.dconf.service
    )
    package_add_library_family keep 'libdconf.so.1*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
