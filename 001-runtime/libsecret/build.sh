#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=libsecret
pkgver=0.21.7

depends=(glib glibc libgcrypt)
builddepends=()
makedepends=(gcc glib-mkenums meson msgfmt ninja pkg-config)

prepare() {
    local archive="$downloaddir/libsecret-$pkgver.tar.xz"
    download \
        "https://download.gnome.org/sources/libsecret/${pkgver%.*}/libsecret-$pkgver.tar.xz" \
        "$archive"
    checksum sha256 6b452e4750590a2b5617adc40026f28d2f4903de15f1250e1d1c40bfd68ed55e "$archive"
    extract "$archive" "$srcdir/libsecret"
}

build() {
    CC="$CC" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
        meson setup "$builddir" "$srcdir/libsecret" \
            --prefix=/usr \
            --libdir=lib \
            --sysconfdir=/etc \
            --localstatedir=/var \
            --buildtype=release \
            --wrap-mode=nodownload \
            -Dcrypto=libgcrypt \
            -Dmanpage=false \
            -Dvapi=false \
            -Dgtk_doc=false \
            -Dintrospection=false \
            -Dbash_completion=disabled \
            -Dtpm2=false \
            -Dpam=false
    meson compile -C "$builddir" -j "$EFILINUX_JOBS"
    DESTDIR="$develdir" meson install -C "$builddir"
}

devel() {
    strip_all "$develdir/usr/bin" "$develdir/usr/lib"
}

package() {
    local -a keep=()
    package_add_library_family keep 'libsecret-1.so.0*'
    [[ ! -x "$pkgdir/usr/bin/secret-tool" ]] || keep+=(/usr/bin/secret-tool)
    package_keep "${keep[@]}"
}

recipe_main "$@"
